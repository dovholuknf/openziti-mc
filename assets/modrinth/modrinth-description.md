# OpenZiti MC

Share a Java Edition server with friends without opening firewall holes. OpenZiti MC routes the game's network traffic
over an [OpenZiti](https://openziti.io) zero-trust overlay. This means the dedicated server never needs a public IP, a
public DNS name, or an open TCP port. Connect by OpenZiti service name. The OpenZiti overlay network will then
authenticate and authorize any connections to your server before a packet ever reaches it.

## What it does

- **Client side:** when you type an OpenZiti service name into "Add Server", the mod intercepts the Netty dial and
  connects over the overlay instead of TCP.
- **Server side:** when enabled in config, the dedicated/integrated server binds on an OpenZiti service instead of a
  normal TCP listener. Only authorized identities on the overlay can reach it.

## Why it works the way it does

The whole mod is three Mixins hooking Netty's `Bootstrap`/`ServerBootstrap` calls and swapping in `ZitiChannelFactory`
+ `ZitiAddress.Dial` / `ZitiAddress.Bind`. Minecraft's packet pipeline is untouched. The OpenZiti JVM SDK is bundled
in the jar, so no extra installs.
Identities are loaded from a standard OpenZiti identity file in `config/openziti/identity.json`. Drop yours in, you
are done.

## Requirements

- Java Edition 1.20.1 (Java 17), 1.21.1 (Java 21), or 1.21.4 (Java 21). Pick the
  release jar tagged with your MC version (`.mc1.20.1`, `.mc1.21.1`, `.mc1.21.4`).
- Fabric Loader. 0.16.x+ for 1.20.1, 0.19.x+ for 1.21.x.
- [Fabric API](https://modrinth.com/mod/fabric-api)
- [Cloth Config](https://modrinth.com/mod/cloth-config) (for the in-game settings UI)
- [ModMenu](https://modrinth.com/mod/modmenu) (recommended -- surfaces the Configure button)
- A running OpenZiti controller and at least one edge router. If you don't have an OpenZiti overlay,
  [set one up by following a get-started guide](https://netfoundry.io/docs/openziti/get-started/network/).

## OpenZiti Setup

The repo includes a `setup-ziti.ps1` script that does all of this interactively and is the recommended way to set up
the OpenZiti overlay.

- create a service (`openziti-mc` by default)
- one identity tagged `#minecraft-server` for the dedicated server, plus one or more identities tagged
  `#minecraft-clients` for each player
- create the matching Bind/Dial service policies

## Server Setup

Drop the enrolled server identity into `config/openziti/identity.json`. Open the in-game **Mods -> OpenZiti MC ->
Configure** screen (or edit `config/openziti.json`), turn **OpenZiti server enabled** on, and set **Service name** to
`openziti-mc` (or whatever you provisioned). The mod closes the vanilla TCP listener once the OpenZiti listener binds,
so nothing is exposed on 25565.

You do not need a dedicated server jar -- a regular Minecraft client with this mod can host via the pause-menu
**Open to LAN** button. Same flow, no port-forwarding, no public IP.

## Client Setup

Drop the enrolled client identity into `config/openziti/identity.json`. That's it. The client-side dial is always
active once the mod is installed -- you do not need to flip the **OpenZiti server enabled** toggle (that's for
hosting). When you want to join, open **Multiplayer -> Add Server**, type the OpenZiti service name in the address
field, and connect.

## Using the Mod

After starting Minecraft, choose: Multiplayer -> Add Server -> Server Address `openziti-mc` -> Done -> Join.

## Additional Information

For additional information or more details see the project's main page on GitHub at
https://github.com/dovholuknf/openziti-mc. There you'll find a full step-by-step (controller + identities +
policies + dev runs) guide as well in [the SETUP.md](https://github.com/dovholuknf/openziti-mc/blob/main/SETUP.md).

## Limitations

- Fabric only. NeoForge / Forge are not supported.
- One jar per MC version -- if you're between target versions (e.g. 1.20.4), there is no compatible build.
- The OpenZiti SDK and Kotlin standard library are bundled, so each jar is around 28-30 MB. Larger than most utility
  mods, smaller than most content mods.
- Annotation-processor warnings about Netty mapping targets are cosmetic; they do not affect runtime behavior.

## Architecture

For a technical deep-dive (Netty channel-factory hook, the smuggler `InetSocketAddress` pattern, the three Mixin
classes, the `ZitiContext` warmup wait, the dial-retry loop) see
[BLOG.md](https://github.com/dovholuknf/openziti-mc/blob/main/BLOG.md) in the repo.

## Credits

- [openziti/ziti-sdk-jvm](https://github.com/openziti/ziti-sdk-jvm) -- the SDK whose `ziti-netty` module made this a
  small mod instead of a large one.
- [vgskye/e4mc-minecraft-architectury](https://github.com/vgskye/e4mc-minecraft-architectury) -- the
  smuggler-InetSocketAddress pattern and the Mixin shapes for `Connection` / `ServerConnectionListener`.

Apache-2.0 licensed. Source at [github.com/dovholuknf/openziti-mc](https://github.com/dovholuknf/openziti-mc).
