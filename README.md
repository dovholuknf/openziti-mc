# OpenZiti MC

A Minecraft (Java Edition, Fabric) mod that routes Minecraft's network traffic over
[OpenZiti](https://openziti.io). Join servers and host worlds over a zero-trust
overlay instead of public TCP -- no port-forwarding, no public DNS, identity-based
access.

- **Modrinth**: https://modrinth.com/mod/openziti-mc
- **Releases**: https://github.com/dovholuknf/openziti-mc/releases

## Supported Minecraft versions

Each release ships three jars, one per supported Minecraft version. Pick the one
matching your installed MC + Fabric Loader profile:

| Jar                                  | Minecraft | Java |
| ------------------------------------ | --------- | ---- |
| `openziti-mc-<ver>+mc1.20.1.jar`     | 1.20.1    | 17   |
| `openziti-mc-<ver>+mc1.21.1.jar`     | 1.21.1    | 21   |
| `openziti-mc-<ver>+mc1.21.4.jar`     | 1.21.4    | 21   |

Same source compiled three times against three MC mapping sets. No feature
differences between jars; pick by your MC version.

## Install (one-shot, players)

From PowerShell on Windows, this downloads OpenZiti MC and its required Fabric
dependencies into your Minecraft mods folder and optionally drops your OpenZiti
identity into place:

```powershell
iwr https://raw.githubusercontent.com/dovholuknf/openziti-mc/main/scripts/install-mods.ps1 | iex
```

(`iwr | iex` runs the script directly without saving it to disk, which sidesteps
Windows' unsigned-script block.)

The script asks for your Minecraft version (`1.20.1`, `1.21.1`, or `1.21.4`) and
picks the matching OpenZiti MC jar.

Or save it locally and pass parameters:

```powershell
iwr https://raw.githubusercontent.com/dovholuknf/openziti-mc/main/scripts/install-mods.ps1 -OutFile install-mods.ps1
Unblock-File .\install-mods.ps1   # strips Windows' "downloaded from internet" marker
.\install-mods.ps1 -MinecraftVersion 1.21.4
```

Prerequisites: the Mojang launcher with **Fabric Loader for your chosen MC version**
installed (https://fabricmc.net/use/installer -> Client -> pick the version).

For the full manual install steps, see [INSTALL.md](INSTALL.md).

## Set up your own OpenZiti service (hosts)

`setup-ziti.ps1` is the controller-side recipe -- create the service, identities, and
policies in one interactive script. See [SETUP.md](SETUP.md) for the full walkthrough.

## Loaders and versions

- Minecraft 1.20.1 (Java 17), 1.21.1 (Java 21), 1.21.4 (Java 21)
- Fabric only. NeoForge is not currently supported.
- OpenZiti via [ziti-sdk-jvm](https://github.com/openziti/ziti-sdk-jvm) (`ziti-netty`
  module). MC 1.20.1 ships with Ziti SDK 0.28.1 (Java 17 cap); MC 1.21.x ships with
  0.33.1.

## Build from source

```
./gradlew build
```

Produces three jars in one shot:

```
mc-1.20.1/build/libs/openziti-mc-<ver>+mc1.20.1.jar
mc-1.21.1/build/libs/openziti-mc-<ver>+mc1.21.1.jar
mc-1.21.4/build/libs/openziti-mc-<ver>+mc1.21.4.jar
```

To build a single MC target:

```
./gradlew :mc-1.21.4:build
```

## Run a dev client

```
./gradlew :mc-1.21.4:runClient   # or :mc-1.21.1: / :mc-1.20.1:
```

## Repo layout

```
common/                          # all version-agnostic Java + Mixin sources
mc-1.20.1/                       # per-version Loom build (Java 17, MC 1.20.1)
mc-1.21.1/                       # per-version Loom build (Java 21, MC 1.21.1)
mc-1.21.4/                       # per-version Loom build (Java 21, MC 1.21.4)
```

Common's source set is pulled into each mc-* module so the same code compiles
against three different MC mapping JARs. No Java code is duplicated across modules.

## License

Apache-2.0. See [LICENSE](LICENSE).
