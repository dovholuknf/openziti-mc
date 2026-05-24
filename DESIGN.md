# ziti-minecraft -- Design

A Minecraft (Java Edition) mod that routes Minecraft's network traffic over
[OpenZiti](https://openziti.io). Players join servers by Ziti service name instead of by
IP/port; dedicated and integrated servers bind on a Ziti service instead of (or in
addition to) a TCP port.

This document captures the v1 architecture. Status: draft, written 2026-05-22.

## Goals

1. A Minecraft client running this mod can join a vanilla-compatible server that is only
   reachable over an OpenZiti overlay -- no public TCP listener, no port-forwarding, no
   public DNS.
2. A Minecraft server (dedicated or integrated) running this mod can bind on a Ziti
   service so authorized identities are the only entities able to reach it.
3. Identity setup is a one-time, file-based step in v1. The identity-loading layer is an
   interface so a future zrok loader can drop in without touching the network code.
4. Ship for Fabric on MC 1.20.1. The codebase is laid out as an Architectury
   multiloader so a second loader module can be added later without restructuring;
   NeoForge is deferred until we bump the MC target to 1.20.4+ where Loom's
   `neoForge()` integration is clean.

## Non-goals (v1)

- In-game enrollment UI. v1 reads an existing identity from disk.
- A custom URI scheme. Service names go in the existing "Server Address" text field.
- Bedrock Edition support. Java only.
- Replacing Minecraft's protocol -- we only swap the transport.
- Per-player ACLs inside the server. Identity-based access is enforced by OpenZiti at
  the overlay layer; the Minecraft server still sees standard player auth.

## High-level architecture

```
+--------------------+        +--------------------+        +--------------------+
|  Minecraft client  |        |   ziti-minecraft   |        |  ziti-sdk-jvm      |
|  (Connection /     | ---->  |  Mixin layer       | ---->  |  ZitiChannel /     |
|   ConnectScreen)   |        |  + IdentityProvider|        |  ZitiServerChannel |
+--------------------+        +--------------------+        +--------------------+
                                       |                              |
                                       v                              v
                              +--------------------+        +--------------------+
                              | Mojmap class hooks |        |   OpenZiti overlay |
                              +--------------------+        +--------------------+
```

We do not implement a tunnel. We replace Minecraft's Netty channel factory and socket
address at well-defined Mixin points so the rest of Minecraft sees a normal Netty
channel that just happens to be backed by Ziti instead of a raw TCP socket.

## Module layout (Architectury)

```
ziti-minecraft/
  common/      -- loader-agnostic code: Ziti integration, identity, address parsing,
                  config, Mixin classes targeting Mojmap-named MC classes.
  fabric/      -- Fabric entrypoints (ModInitializer / ClientModInitializer),
                  fabric.mod.json, fabric-side mixin registration.
  (neoforge/)  -- planned for the post-1.20.4 bump.
```

Common code is compiled against Mojmap-named Minecraft. Each loader module applies the
common code plus its own glue.

## Key types

### `IdentityProvider` (common, pluggable)

```java
public interface IdentityProvider {
    /** Load (or enroll on first use) a Ziti context. Idempotent. */
    ZitiContext load() throws IOException;
    /** Human-readable label for logs and UI. */
    String describe();
}
```

v1 implementation: `FileIdentityProvider(Path)`. Accepts either a `.jwt` (enrolls and
writes the resulting `.json` next to it) or an already-enrolled `.json` (loads it
directly).

Planned post-v1: `ZrokIdentityProvider`. zrok is built on OpenZiti and produces share
tokens / reserved shares; the loader will resolve a zrok share token into the underlying
Ziti context.

### `ZitiNetwork` (common)

Singleton-ish holder for the loaded `ZitiContext`, called by Mixin code. Lazy-loaded
on first use (first connect attempt or first server bind), so a player with no
identity configured never trips a load failure.

### `ZitiServiceAddress` (common)

Parses the string the user types into the "Server Address" field. Detection rule for
v1: if the string contains no `.` and is not a numeric IPv4, treat as a Ziti service
name. Configurable to a stricter "must start with `ziti:`" prefix mode for users who
want to be explicit.

### Mixin targets (Mojmap names)

| MC class                                              | Hook                                            | Purpose                                                                    |
| ----------------------------------------------------- | ----------------------------------------------- | -------------------------------------------------------------------------- |
| `net.minecraft.network.Connection`                    | `@Redirect` on the `Bootstrap.channel(...)` and `.connect(...)` calls | Use `ZitiChannel.class` and `ZitiAddress.Dial(serviceName)` when the destination is a Ziti service. |
| `net.minecraft.client.multiplayer.resolver.ServerAddress` | `@Inject` on `parseString` | Recognize Ziti-service-name inputs so the resolver pipeline does not reject them. |
| `net.minecraft.client.multiplayer.resolver.ServerNameResolver` | `@Inject` on `resolveAddress` | Short-circuit DNS lookup for Ziti service names.                            |
| `net.minecraft.server.network.ServerConnectionListener` | `@ModifyArg` / `@Inject` on `startTcpServerListener` | Add a `ZitiServerChannel` bind alongside (or instead of) the TCP listener. |

We will follow the `@Redirect` / `@ModifyArg` style e4mc uses rather than full method
rewrites. This minimizes conflict surface with other networking mods (Krypton,
ViaFabricPlus, etc.).

### Configuration

Config file: `config/openziti.json`, schema (as shipped):

```json
{
  "identityPath": "config/openziti/identity.json",
  "serverEnabled": false,
  "serviceName": "openziti-mc"
}
```

- `serverEnabled`: opt-in for the server-side bind so single-player worlds and
  client installations don't spin up a Ziti listener they don't need. When true the
  vanilla TCP listener is also closed (zero-trust posture).
- `serviceName`: the OpenZiti service to bind on. Only used when `serverEnabled` is
  true.
- The initial `addressDetection` enum (implicit / prefix) was removed during v0.2.x
  simplification -- the implicit heuristic with a `localhost`/`local`/`lan`
  deny-list is the only mode now.

## Loader differences worth flagging

- **Fabric** uses `fabric.mod.json` and Mixin registration via `fabric.mod.json` ->
  `mixins`. Entrypoints: `main` for server-safe init, `client` for client-only init.
- **NeoForge 1.20.1** still uses legacy Forge `mods.toml` and bus-event subscription.
  Mixin registration is via `MixinExtrasBootstrap`-equivalent + a service file
  (NeoForge supports the same `mixins.json` config; loader hooks `MixinBootstrap` for
  us).

Both loaders pull from `common/` via Architectury Loom's `transformDevelopmentFabric` /
`transformDevelopmentNeoForge` tasks. We compile common Mixins against MC and remap on
build per loader.

## Failure modes and what we do

| Failure                                  | Behavior                                                                 |
| ---------------------------------------- | ------------------------------------------------------------------------ |
| Identity file missing                    | Log a friendly warning. Mod stays loaded; vanilla TCP path unaffected.   |
| Identity enrollment (jwt) fails          | Log error with the underlying ZitiException. No retry loop in v1.        |
| User types a Ziti name with no identity  | Toast in-game ("ziti identity not loaded -- check config/openziti.json"). |
| Server bind enabled, service not granted | Server logs error, falls back to TCP listener if also configured.        |
| Ziti SDK throw mid-connect               | Treat as connection failure -- MC shows its standard "could not connect". |

## Open questions

1. **Should v1 disable the TCP listener when server-bind-Ziti is enabled?** Defaulting
   to "Ziti only" gives the strongest security story but breaks LAN play. Probably:
   keep TCP on for `127.0.0.1` only, Ziti for everyone else.
2. **Do we need a server allowlist of Ziti identity names mapped to in-game usernames?**
   Probably not in v1 -- the overlay already authorizes who can reach the listener, and
   in-game auth is unchanged. Revisit if abuse shows up.
3. **Will MC's Netty version stay compatible with `ziti-netty` 0.28.x?** Need a smoke
   test on first build; bump if needed.
