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
4. Ship for Fabric on MC 1.20.1, 1.21.1, and 1.21.4. The codebase is laid out as one
   shared `common/` source folder pulled into per-MC-version Loom modules, so the
   same source compiles three times against three MC mapping sets. NeoForge / Forge
   are not currently supported.

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

## Module layout

```
ziti-minecraft/
  common/      -- ALL Java source: Ziti integration, identity, address parsing,
                  config, Fabric ModInitializer entrypoints, Mixin classes targeting
                  Mojmap-named MC classes. Not a Gradle subproject.
  mc-1.20.1/   -- per-MC-version Loom build (Java 17, Fabric Loader 0.16+,
                  Cloth 11, ModMenu 7, Ziti SDK 0.28.1).
  mc-1.21.1/   -- per-MC-version Loom build (Java 21, Cloth 15, ModMenu 11,
                  Ziti SDK 0.33.1).
  mc-1.21.4/   -- per-MC-version Loom build (Java 21, Cloth 17, ModMenu 13,
                  Ziti SDK 0.33.1).
```

Each `mc-X.Y.Z/build.gradle` declares `sourceSets.main.java.srcDir
"${rootDir}/common/src/main/java"` so Loom compiles common's source against that
module's MC mappings. There is no per-version Java source duplication; the principle
is "code in common unless the compiler forces a split." All Mixin targets so far
(`Connection`, `ServerConnectionListener`, Netty `Bootstrap`) are stable across the
three MC versions, so no splits exist today.

Dropping Architectury (which was load-bearing only for multi-loader Fabric+NeoForge)
let us go to plain `fabric-loom` directly with cleaner per-module configuration.

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

## MC-version differences worth flagging

- **1.20.1** is Java 17 and pins the Ziti SDK at 0.28.1 (0.29+ targets Java 21 only).
  Cloth Config 11.x, ModMenu 7.x.
- **1.21.1** is Java 21 with the broader 1.21 modding audience baseline. Cloth Config
  15.x, ModMenu 11.x. Ziti SDK 0.33.1.
- **1.21.4** is Java 21 with the newest Cloth Config 17.x and ModMenu 13.x. Ziti SDK
  0.33.1.

All three pull from `common/` via a Gradle source-set extension. `fabric.mod.json`
lives per-module because the MC version pin and dependency floors differ; the source
files (Java + `openziti.mixins.json`) come from `common/` unchanged.

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
