# OpenZiti MC

A Minecraft (Java Edition, Fabric) mod that routes Minecraft's network traffic over
[OpenZiti](https://openziti.io). Join servers and host worlds over a zero-trust
overlay instead of public TCP -- no port-forwarding, no public DNS, identity-based
access.

- **Modrinth**: https://modrinth.com/mod/openziti-mc
- **Releases**: https://github.com/dovholuknf/openziti-mc/releases

## Install (one-shot, players)

From PowerShell on Windows, this downloads OpenZiti MC and its four required Fabric
dependencies into your Minecraft mods folder and optionally drops your OpenZiti
identity into place:

```powershell
iwr https://raw.githubusercontent.com/dovholuknf/openziti-mc/main/scripts/install-mods.ps1 | iex
```

Or save and run with parameters:

```powershell
iwr https://raw.githubusercontent.com/dovholuknf/openziti-mc/main/scripts/install-mods.ps1 -OutFile install-mods.ps1
.\install-mods.ps1
```

Prerequisites: the Mojang launcher with **Fabric Loader for Minecraft 1.20.1**
installed (https://fabricmc.net/use/installer -> Client -> 1.20.1).

For the full manual install steps, see [INSTALL.md](INSTALL.md).

## Set up your own OpenZiti service (hosts)

`setup-ziti.ps1` is the controller-side recipe -- create the service, identities, and
policies in one interactive script. See [SETUP.md](SETUP.md) for the full walkthrough.

## Loaders and versions

- Minecraft 1.20.1 (LTS)
- Java 17
- Fabric. NeoForge is planned for when we bump the MC target to 1.20.4+; on 1.20.1
  the NeoForge tooling story is rough and Fabric covers the install base.
- OpenZiti via [ziti-sdk-jvm](https://github.com/openziti/ziti-sdk-jvm) (`ziti-netty`
  module)

## Build from source

```
./gradlew build
```

Output jar lands at `fabric/build/libs/openziti-fabric-<version>.jar`.

## Run a dev client

```
./gradlew :fabric:runClient
```

## License

Apache-2.0. See [LICENSE](LICENSE).
