# ziti-minecraft

A Minecraft (Java Edition) mod that routes Minecraft's network traffic over
[OpenZiti](https://openziti.io). Join servers and host worlds over a zero-trust overlay
instead of public TCP -- no port-forwarding, no public DNS, identity-based access.

**Status:** scaffolding. The build compiles; behavior is being implemented. See
[DESIGN.md](DESIGN.md) for the architecture.

## Loaders and versions

- Minecraft 1.20.1 (LTS)
- Java 17
- Fabric (NeoForge is planned for when we bump the MC target to 1.20.4+ -- on 1.20.1
  the NeoForge tooling story is rough and Fabric has the install base)
- Architectury multiloader scaffolding is in place so a second loader module can be
  dropped in without restructuring the source tree
- OpenZiti via [ziti-sdk-jvm](https://github.com/openziti/ziti-sdk-jvm) (`ziti-netty`
  module)

## Build

```
./gradlew build
```

Outputs:

- `fabric/build/libs/openziti-fabric-<version>.jar`

## Run a dev client

```
./gradlew :fabric:runClient
```

## Configure an identity

The mod expects a Ziti identity file at `config/openziti/identity.json` (relative to
the Minecraft instance directory). Drop in either:

- A `.json` already-enrolled identity (preferred), or
- A `.jwt` enrollment token -- the mod will enroll on first use and write the resulting
  `.json` next to it.

Path is configurable in `config/openziti.json`.

## License

Apache-2.0. See [LICENSE](LICENSE).
