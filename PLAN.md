# ziti-minecraft -- Plan and Build Log

What we set out to build, the decisions we made along the way, and the state of the code
as of the first working client-connect path. Maintained as a running record so a future
session (mine or someone else's) can pick up without re-deriving the reasoning.

## 1. Goal

Build a Minecraft Java Edition mod that routes Minecraft's client and server network
traffic over an OpenZiti overlay instead of (or in addition to) public TCP. Players join
each other's worlds by Ziti service name; no port-forwarding, no public DNS, identity-
based access enforced by the overlay.

## 2. Constraints we locked in up front

| Decision                | Choice                                                        | Reasoning                                                                                                                                            |
| ----------------------- | ------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| Modloader               | Architectury multiloader (Fabric + planned NeoForge)          | Reach both audiences from one codebase. The structural cost is low; the maintenance cost of forking later is high.                                   |
| Sides                   | Client and server                                             | Client dial is the headline feature; server bind is the other half of the security story (no public listener).                                       |
| Addressing in MC UI     | Ziti service name in the existing "Server Address" field      | Cleanest UX, no custom scheme, fits MC's "Add Server" flow without a new screen.                                                                     |
| Identity                | File-path loader (configurable), with a pluggable interface   | v1 reads `.json` from a config-pointed path. zrok loader is planned for v1.x and must drop in without touching the Netty hooks.                       |
| Minecraft version       | 1.20.1 (LTS)                                                  | Biggest install base in the 1.20.x line. Cost: rougher NeoForge tooling story; we accepted that and dropped NeoForge from v1.                         |
| Mappings                | Mojmap                                                        | What Architectury's templates default to and what NeoForge requires upstream. One mapping set across all loader modules.                              |
| Java                    | 17 (Temurin)                                                  | Required by MC 1.20.1; LTS; the JVM ecosystem standard for MC modding.                                                                               |
| License                 | Apache-2.0                                                    | Matches `ziti-sdk-jvm`. Permissive, patent-grant.                                                                                                    |

## 3. Architectural choice we kept coming back to

Minecraft's networking is Netty 4.x all the way down. The OpenZiti JVM SDK ships a
`ziti-netty` module with `ZitiChannel` / `ZitiServerChannel` / `ZitiChannelFactory` /
`ZitiServerChannelFactory` -- drop-in Netty channels that speak Ziti instead of TCP.

That collapsed the design space: we do not implement a tunnel, we do not run a relay,
we do not rewrite Minecraft's protocol layer. We hook Minecraft's Netty `Bootstrap`
calls at three Mixin points and let the SDK do the heavy lifting. Everything else --
identity, address parsing, config -- is glue.

## 4. The build log (chronological)

### 4.1 Scaffold

- Wrote `settings.gradle`, root `build.gradle`, `gradle.properties` pinning MC 1.20.1,
  Java 17, Architectury Loom 1.4 (later bumped), Architectury API 9.2.14, Fabric Loader
  0.15.11, Fabric API 0.92.5+1.20.1, NeoForge 47.1.106 (later dropped), OpenZiti 0.28.1.
- Created `common/`, `fabric/`, `neoforge/` modules following Architectury's standard layout.
- Wrote `common/src/main/java/org/openziti/minecraft/` packages: `ZitiMc`, `config/ZitiMcConfig`,
  `address/ZitiServiceAddress`, `identity/IdentityProvider` + `FileIdentityProvider`, and
  three Mixin stub classes (`ConnectionMixin`, `ServerAddressMixin`,
  `ServerConnectionListenerMixin`).
- Wrote Fabric entrypoints (`ZitiMcFabric` + `ZitiMcFabricClient`), `fabric.mod.json`,
  Mixin config (`openziti.mixins.json`).
- Wrote NeoForge entrypoint, `mods.toml`, `pack.mcmeta`.
- Bundled the OpenZiti runtime into the Fabric/NeoForge jars via Gradle shadow so users
  do not need a separate install.

### 4.2 Toolchain

- Installed Temurin JDK 17 via chocolatey.
- Downloaded Gradle 8.6 into `D:/tools/gradle/8.6/` (and the zip under
  `D:/tools/gradle/downloads/`) and used it once to generate the project's Gradle
  wrapper. The wrapper handles its own distribution from then on.
- Added `.claude/settings.local.json` allowing the gradle commands so the agent stops
  prompting for permission on every invocation.

### 4.3 First build round (failures and fixes)

Each error we hit and what it told us:

1. **`No such property: mod_id for class: java.lang.Boolean`** -- the `loom {
   accessWidenerPath = ... }` block in `common/build.gradle` was tripping a Groovy DSL
   resolution corner. The access widener we added was empty anyway; removing the file
   and the loom block fixed it. Lesson: do not scaffold a file you don't need yet.
2. **`This version of loom does not support the mixin remap type value`** -- Architectury
   API 9.2.14 needs Loom 1.5+. Bumped `archloom_version` from 1.4 to 1.6-SNAPSHOT. Common
   and Fabric now configured clean.
3. **`Could not find method neoForge() for arguments [net.neoforged:neoforge:47.1.106]`**
   -- the show-stopper. NeoForge 47.x (the MC 1.20.1 line) is essentially a Forge fork
   with the legacy userdev structure; Loom's `neoForge()` integration is for NeoForge
   20.4+ with the new MDG-based userdev. Tried switching to Architectury's `forge()`
   plugin, same error -- the dependency configuration name is platform-specific.
   Resolution: drop NeoForge from v1 on 1.20.1 entirely. Multiloader scaffolding stays;
   we add NeoForge back when we bump the MC target to 1.20.4+ where the tooling is clean.

After dropping NeoForge: `gradle build` produced `fabric/build/libs/openziti-fabric-0.1.0.jar`
(~28 MB, includes Ziti SDK + Netty integration + Kotlin stdlib).

### 4.4 Probing the Ziti SDK API surface

Used `javap` against the shadowed jar to confirm exact signatures before writing the
Mixins. Key findings:

- `org.openziti.Ziti.newContext(File, char[]) : ZitiContext` -- loads from an enrolled
  identity JSON. We use the file overload.
- `org.openziti.ZitiAddress.Dial` has Java-friendly constructors including the simplest
  `Dial(String service)`. That's the `SocketAddress` we hand to Netty's `connect`.
- `org.openziti.netty.ZitiChannelFactory(ZitiContext) implements ChannelFactory<Channel>`
  -- exactly the shape `AbstractBootstrap.channelFactory(ChannelFactory)` expects.
- `org.openziti.ZitiContext` is the central Kotlin interface; we hold one instance in
  `ZitiMc`, lazily loaded on first use.

### 4.5 Implementation pass (the real work)

Files written or rewritten in this pass:

- `address/ZitiSocketAddress.java` -- a tiny `InetSocketAddress` subclass that smuggles
  a Ziti service name through MC's resolution pipeline. Modeled after e4mc's
  `SmugglersInetSocketAddress`.
- `identity/IdentityProvider.java` -- return type tightened from `Object` to
  `org.openziti.ZitiContext` now that we have the SDK on the compile classpath.
- `identity/FileIdentityProvider.java` -- real `Ziti.newContext(File, char[])` call for
  `.json` identities, with a friendly error for `.jwt` (we deferred in-process enrollment
  to a later release; the user can run `ziti edge enroll --jwt ...` to produce a `.json`).
- `ZitiMc.java` -- added `zitiContext()` static accessor with double-checked locking,
  lazy load on first call.
- `mixin/ServerNameResolverMixin.java` -- HEAD-inject cancellable on
  `ServerNameResolver.resolveAddress` that short-circuits DNS for Ziti service names and
  returns a `ResolvedServerAddress` whose `asInetSocketAddress` is a `ZitiSocketAddress`.
- `mixin/ConnectionMixin.java` -- HEAD-inject captures the Ziti service name from
  `ZitiSocketAddress` into a ThreadLocal; `@Redirect` on Netty's
  `AbstractBootstrap.channel(Class)` substitutes a `ZitiChannelFactory`; `@Redirect`
  on `Bootstrap.connect(InetAddress, int)` substitutes a `ZitiAddress.Dial(service)`.
- `mixin/ServerAddressMixin.java` -- deleted. MC's `ServerAddress.parseString` already
  accepts arbitrary host strings, so this stub was dead weight.
- `openziti.mixins.json` -- updated to list the three live Mixins (one common, two client).

### 4.6 Compile errors and how we fixed them

1. **`ServerNameResolverMixin is interface, target is not interface`** -- changed from
   `interface` (with `default` method) to `abstract class` (with `private` method).
2. **Generics complaint on `bootstrap.channel(channelClass)`** -- `AbstractBootstrap<?, ?>`
   loses its `<C extends Channel>` type info. Switched to raw `AbstractBootstrap` /
   `Class` and added `@SuppressWarnings({"rawtypes", "unchecked"})`. Acceptable for
   Mixin-handler code.
3. **`getHostIp()` not overridden on anonymous `ResolvedServerAddress`** -- added the
   stub returning `"127.0.0.1"`. The value is never used because we hijack the connect
   before any TCP op runs.

### 4.7 Cosmetic warnings: what we silenced and what we left

The Mixin annotation processor was warning on every build:

```
Unable to locate method mapping for @At(INVOKE.<target>) 'Lio/netty/bootstrap/...'
```

The AP tries to remap every `@At` target against MC's mapping data. Netty is not in
that data, so it warned. Adding `remap = false` to the relevant `@At` blocks in
`ConnectionMixin` tells the AP to skip the remap check; warnings are now gone. The
server-bind Mixin used `remap = false` from the start.

One warning remains and is parked:

```
You are using an outdated version of Architectury Loom!
```

The `architectury-plugin` compares our pinned Loom (1.6.422, the last that cleanly
supports MC 1.20.1) against its idea of "latest" (1.10+ era, targets MC 1.21+). The
warning is cosmetic. Revisit when we bump the MC target -- the version bump silences
it for free.

### 4.8 ConnectionMixin target descriptor fix

First runClient crashed with `Critical injection failure: ... Scanned 0 target(s)` on
the `swapChannelFactory` Redirect. Cause: the `@At` target used owner
`io/netty/bootstrap/AbstractBootstrap`, but MC's bytecode references `channel(Class)`
via `io/netty/bootstrap/Bootstrap` (the static call-site type), even though the method
is inherited from `AbstractBootstrap`. Mixin INVOKE matching is bytecode-exact, so the
owner string has to be `Bootstrap`. One-word fix; landed.

### 4.9 ZitiContext warmup race

On the very first dial after `ZitiMc.zitiContext()` returned, the SDK was still
authenticating with the controller asynchronously; the dial fired before the service
catalog was populated and got `ServiceNotAvailable`. Fix: `zitiContext()` now blocks
inside its synchronized block until `ctx.getStatus()` reports `Status.Active` (or hits
a terminal failure like `NotAuthorized`/`Unavailable`/`Disabled`, or a 15 s deadline).
The first dial pays one warm-up tax; subsequent dials are unaffected.

### 4.10 Fabric Loader bump and dev runtime classpath fix

Two follow-ups discovered during the first `:fabric:runClient`:

1. Fabric API 0.92.5+1.20.1 requires Fabric Loader 0.16.10+. Our pin was 0.15.11.
   Bumped `fabric_loader_version` to 0.16.14 and the `fabric.mod.json` `fabricloader`
   constraint to `>=0.16.10`.
2. The Ziti SDK was bundled into the production jar via Shadow but NOT on the dev
   runtime classpath, causing `ClassNotFoundException: org.openziti.netty.ZitiChannelFactory`
   at mod init. Added `implementation` declarations for `org.openziti:ziti` and
   `ziti-netty` alongside the existing `shadowBundle` declarations so Loom's dev
   runtime sees them. Shadow still owns the production bundle (with transitives:
   Kotlin stdlib, jackson, BouncyCastle, etc).

### 4.11 Server-bind Mixin implemented

`ServerConnectionListenerMixin` is no longer a stub. It uses two `@ModifyArg` hooks
on `startTcpServerListener` to capture vanilla's child handler and event loop group,
then `@Inject(at = @At("TAIL"))` stands up a second `ServerBootstrap` with
`ZitiServerChannelFactory(ZitiMc.zitiContext())`, binds to
`ZitiAddress.Bind(serviceName)`, and appends the resulting `ChannelFuture` to the
`@Shadow`'d `channels` list so vanilla's `stop()` closes it. Gated on
`config.serverBind.enabled`.

## 5. Current state

- `./gradlew build` is green. Two cosmetic Netty-mapping warnings are silenced with
  `remap = false`; the Architectury "outdated Loom" warning is parked.
- Output jar: `fabric/build/libs/openziti-fabric-0.1.0.jar`.
- **Client connect** path wired end-to-end and validated against a real Ziti controller
  (`sg4:1280`): server-name resolver short-circuits, smuggler address flows through,
  Ziti Bootstrap dials by service name.
- **Server bind** path wired end-to-end and validated: server logs
  `Ziti listener bound on service 'openziti-mc'`, controller logs the bind session.
- The first MC client connect over Ziti **reached the server's protocol layer**: server
  saw a `GameProfile` for the dialing identity (`callerId=client-mc` visible in the
  Session toString). End-to-end transport over Ziti is proven.
- Open at time of writing: client gets `lost connection: Disconnected` immediately
  after Login Start. Most likely cause is vanilla `server.properties` defaulting to
  `online-mode=true` so the server tries to Mojang-auth the dev client's offline
  profile and boots it. Workaround: `online-mode=false` in `run-server/server.properties`.

## 6. What's next

In order:

1. **Confirm in-world join.** With `online-mode=false`, the client should fully load
   into the world. That closes v1.
2. **In-process JWT enrollment** in `FileIdentityProvider` so users do not need the
   `ziti` CLI for first-time setup. Needs PKCS12 keystore management.
3. **Bump MC target to 1.20.4+ (or 1.21.x)** and re-add NeoForge. The Architectury
   scaffolding is already shaped for it. This bump also silences the parked
   "outdated Architectury Loom" warning -- see [memory note](../../C:\Users\claude\.claude\projects\D--git-github-dovholuknf-ziti-minecraft\memory\project_loom_outdated_warning.md)
   (not in repo, in the agent's auto-memory).
4. **`ZrokIdentityProvider`.** Same `IdentityProvider` interface; resolves a zrok share
   token into the underlying Ziti context.
5. **Polish.** A CI workflow (build + remap), maybe a Modrinth listing, possibly an
   in-game enrollment screen replacing the file-only flow.
