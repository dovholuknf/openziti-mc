# ziti-minecraft -- Setup Guide

End-to-end recipe for joining a Minecraft server over OpenZiti instead of TCP. Everything
below is what the working v1 dev environment uses; commands are PowerShell-flavored and
match the exact controller objects exported from a known-good install (see
`minecraft.export.json` in this repo).

## Prerequisites

1. **A running OpenZiti controller** (any version v0.x or v1.x). Public endpoint reachable
   from both the player's machine and the server's machine.
2. **At least one edge router** registered with the controller, with the
   `public` attribute. Router does not need to be on the public internet -- only reachable
   from the controller's network plus the two endpoints.
3. **`ziti` CLI** on your admin workstation, logged into the controller
   (`ziti edge login <controller>:1280 -u admin -p <pw>`).
4. **Minecraft + Java**. Pick a supported target:
   - MC 1.20.1 needs Java 17 (Temurin recommended).
   - MC 1.21.1 or 1.21.4 needs Java 21 (Temurin recommended).
5. The mod jar from `mc-<version>/build/libs/openziti-mc-<ver>.mc<version>.jar` on
   both client and server.

If you do not have a controller yet, the fastest path is
`ziti edge quickstart` (single binary, all-in-one for dev).

## 1. Create identities

Two identities. One **binds** the service (your dedicated server). One **dials** the
service (your player). The identity files are downloaded as JWT enrollment tokens that
get converted to long-lived `.json` identities in step 4.

Tag each identity with a role attribute so the service policies in step 3 grant access
by **attribute** rather than by specific identity name. That way adding a second
player later is just `ziti edge create identity player2 --role-attributes minecraft-clients`
with no policy edits.

```powershell
# The dedicated server's identity, tagged for the bind policy
ziti edge create identity server-mc --role-attributes minecraft-server -o server-mc.jwt
# The player's identity, tagged for the dial policy
ziti edge create identity client-mc --role-attributes minecraft-clients -o client-mc.jwt
```

Two `.jwt` files now sit in your current directory. They are single-use enrollment
tokens; copy them to the machine where each identity will run before enrolling.

## 2. Create the service

```powershell
# A bare service. No address configs needed -- the mod dials and binds by service name
# directly, not via an intercept/host config.
ziti edge create service openziti-mc
```

Defaults that matter:
- `terminatorStrategy: smartrouting` -- the router picks the best terminator if there
  are several (good for failover; for one binder it makes no difference).
- `encryptionRequired: true` -- end-to-end Ziti payload encryption on top of the edge
  router's TLS. Leave it on.

## 3. Authorize the identities

Three policies. Two on the service (bind + dial), one for edge-router access. Policies
match identities by **role attribute** (`#minecraft-server`, `#minecraft-clients`)
rather than by specific name. Anything tagged with the right attribute is in scope.

```powershell
# Anything tagged #minecraft-server can BIND openziti-mc (run a listener)
ziti edge create service-policy mc-bind Bind `
    --service-roles '@openziti-mc' --identity-roles '#minecraft-server'
# Anything tagged #minecraft-clients can DIAL openziti-mc (connect to a listener)
ziti edge create service-policy mc-dial Dial `
    --service-roles '@openziti-mc' --identity-roles '#minecraft-clients'
# Both tag sets can reach the public-attributed edge routers
ziti edge create edge-router-policy mc-erp `
    --edge-router-roles '#public' --identity-roles '#minecraft-server,#minecraft-clients'
# openziti-mc is reachable via public-attributed edge routers
ziti edge create service-edge-router-policy mc-serp `
    --service-roles '@openziti-mc' --edge-router-roles '#public'
```

If your controller already has wildcard policies for `#all` identities on `#public`
routers (the `ziti edge quickstart` setup does), `mc-erp` and `mc-serp` are redundant
but harmless. Keeping them explicit makes the setup self-contained.

## 4. Enroll the identities

Convert each `.jwt` (single-use) into a `.json` (long-lived):

```powershell
ziti edge enroll --jwt server-mc.jwt -o server-mc.json
ziti edge enroll --jwt client-mc.jwt -o client-mc.json
```

The `.jwt` files are consumed; keep the `.json` files safe. Each one carries a unique
private key that authenticates as that identity.

## 5. Drop the identities into the mod's config dirs

For dev runs via `./gradlew :mc-1.21.4:runClient` and `:mc-1.21.4:runServer`, working
dirs are `run/` and `run-server/` respectively. Replace `mc-1.21.4` with `mc-1.21.1` or
`mc-1.20.1` to dev against a different MC target. For a real Minecraft instance,
replace those with your launcher's instance directory.

```powershell
# Client side -- where the player runs MC
New-Item -ItemType Directory -Force -Path .\run\config\openziti
Move-Item .\client-mc.json .\run\config\openziti\identity.json
# Server side -- where the dedicated server runs
New-Item -ItemType Directory -Force -Path .\run-server\config\openziti
Move-Item .\server-mc.json .\run-server\config\openziti\identity.json
```

## 6. Configure the mod

Open the in-game **Mods -> OpenZiti MC -> Configure** screen (ModMenu). The screen
shows a status block at the top (identity-file presence, Ziti context state) and two
editable fields:

- **OpenZiti server enabled** -- opt-in for hosting via Open-to-LAN. Off by default
  because most users are client-only. When on: the integrated server (the one MC
  spins up when you click "Open to LAN" in the pause menu) binds on the OpenZiti
  service in place of its TCP listener -- zero-trust posture. When off: this MC
  install is client-only and can still dial *other* peoples' Ziti services in Add
  Server. **Not necessary if you run a separate dedicated server** -- the dedicated
  server has its own copy of the mod and its own config.
- **Service name** -- the OpenZiti service to bind on. Used only when **OpenZiti
  server enabled** is on.

The identity file path is not exposed in the UI -- the mod loads from
`config/openziti/identity.json` relative to the Minecraft instance directory. Power
users can override by hand-editing `config/openziti.json`.

Equivalent JSON in `config/openziti.json`:

```json
{
  "identityPath": "config/openziti/identity.json",
  "serverEnabled": true,
  "serviceName": "openziti-mc"
}
```

Both the client install and the server install use the same schema. The only
substantive difference is the identity file on each side and whether
**serverEnabled** is on (off on a pure-client install, on for a host that uses
Open-to-LAN). All fields require a restart; Cloth Config prompts for one
automatically after Save.

## 7. Dev-only: turn off Mojang auth on the server

The `:mc-1.21.4:runClient` task uses an offline `Player###` profile. Vanilla
`server.properties` defaults to `online-mode=true`, which tries to verify that player
with Mojang and boots them. For dev testing:

```powershell
(Get-Content .\run-server\server.properties) -replace '^online-mode=true','online-mode=false' | Set-Content -Encoding UTF8 .\run-server\server.properties
```

Production deployments behind Ziti should usually leave `online-mode=true` so real
Mojang-auth still applies on top of overlay identity-auth.

Also accept the Mojang EULA:

```powershell
"eula=true" | Set-Content -Encoding UTF8 .\run-server\eula.txt
```

## 8. Run

```powershell
# Window 1: dedicated server
./gradlew :mc-1.21.4:runServer
```

Wait for these log lines:
```
[ziti-minecraft] ziti-minecraft init: identity provider = file:config\openziti\identity.json
[ziti-minecraft] Binding Minecraft server to Ziti service 'openziti-mc'
[ziti-minecraft] Ziti listener bound on service 'openziti-mc'
... Done (Xs)!
```

Then in a second window:

```powershell
# Window 2: dev client
./gradlew :mc-1.21.4:runClient
```

In Minecraft: **Multiplayer -> Add Server**. Server Address: `openziti-mc`. Done.
Click **Join Server**.

Expected log lines on the client:
```
[ziti-minecraft] Resolving 'openziti-mc' as Ziti service
[ziti-minecraft] Dialing Ziti service openziti-mc
... Loaded N advancements
```

You are now playing Minecraft over an OpenZiti overlay. No port forwarding, no public
TCP listener, identity-authenticated by the controller.

## Bonus: host from a client via Open to LAN

You do **not** need a dedicated server jar. Every Minecraft Java client has the
dedicated-server code built in -- it's how "Open to LAN" works. With this mod:

1. Friend A (the host) launches MC with the mod, loads a single-player world, and
   clicks **Open to LAN** in the pause menu.
2. With **OpenZiti server enabled** on and **Service name** set, the integrated
   server binds on the OpenZiti service the same way a dedicated server would.
   Friend A's machine never exposes a TCP port and never needs a public IP.
3. Friend B (the joiner) launches MC with the mod, opens **Multiplayer -> Add
   Server**, types the service name, and joins.

Friend A's identity needs Bind permission on the service (the `#minecraft-server`
attribute from step 1). Friend B's identity needs Dial permission
(`#minecraft-clients`). Same controller setup, no dedicated server required.

## Diagnostic: `ziti edge policy-advisor`

Before launching Minecraft, you can verify any identity's Dial/Bind access to a
service:

```powershell
ziti edge policy-advisor identities -q <identity-name>
```

Expected output for a client identity:

```
OKAY : client-mc (1) -> openziti-mc (1) Common Routers: (1/1) Dial: Y Bind: N
```

For a server-bind identity it should show `Dial: N Bind: Y`. If `Common Routers: 0/1`
the identity has no edge router it can reach. If `Dial: N` or `Bind: N` the relevant
service policy doesn't match the identity's role attributes; fix with `ziti edge update
identity <name> --role-attributes <attr>`.

This single command catches the most common smoke-test failure -- "the connection
just doesn't work" almost always traces back to a policy/role mismatch you can spot
here without ever launching MC.

## Troubleshooting

| Symptom                                                          | Cause                                                                                                   | Fix                                                                                          |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| Client logs `ServiceNotAvailable`                                | First dial races the SDK's catalog sync                                                                 | Already handled by the mod's catalog-wait + 5-retry loop. If persistent, check service policies. |
| Client logs `exceeded maximum [2] retries creating circuit`      | Edge router cannot reach the binder. Either binder is down, or no `mc-erp` / `mc-serp` policies         | Verify `ziti edge list terminators` shows your service, server log shows `Ziti listener bound` |
| `lost connection: Disconnected` immediately after Login Start    | `online-mode=true` on the server, dev client is offline                                                 | Set `online-mode=false` for dev (see step 7)                                                  |
| `ClassNotFoundException: org.openziti.netty.ZitiChannelFactory` at startup | Mod jar is missing the bundled Ziti SDK                                                            | Rebuild with `./gradlew build`; production jars are at `mc-<version>/build/libs/openziti-mc-*.mc*.jar` |
| Mod's `init` logs no identity path                               | `config/openziti.json` missing or unreadable                                                            | The mod writes defaults on first launch; check working dir matches the run task (`run/` vs `run-server/`) |
| Server log shows `Closing vanilla TCP listener(s)`               | Expected behavior when **OpenZiti server enabled** is on                                                | This is the zero-trust posture. To get the TCP listener back, turn the toggle off.            |

## Finding the logs

When Minecraft is launched via `:mc-1.21.4:runClient`/`runServer`, log output streams to
the gradle window. When launched via a real launcher (official Mojang launcher,
Modrinth App, Prism, MultiMC, etc.), Log4j2 writes to a file under the instance
directory:

| Launcher / target          | Path                                                                                  |
| -------------------------- | ------------------------------------------------------------------------------------- |
| Official launcher (Win)    | `%APPDATA%\.minecraft\logs\latest.log` (`C:\Users\<you>\AppData\Roaming\...`)         |
| Official launcher (macOS)  | `~/Library/Application Support/minecraft/logs/latest.log`                             |
| Official launcher (Linux)  | `~/.minecraft/logs/latest.log`                                                        |
| Modrinth App               | `%APPDATA%\com.modrinth.theseus\profiles\<name>\logs\latest.log` (or platform equiv) |
| Prism / MultiMC / ATLauncher | `<launcher-instance-dir>/.minecraft/logs/latest.log`                                |
| Dedicated server           | `<server-dir>/logs/latest.log`                                                       |

Older logs rotate to `logs/<yyyy-mm-dd>-N.log.gz` in the same folder.

To tail the log live from PowerShell while playing:

```powershell
Get-Content -Wait "$env:APPDATA\.minecraft\logs\latest.log"
```

Filter to just the mod's lines:

```powershell
Get-Content -Wait "$env:APPDATA\.minecraft\logs\latest.log" | Where-Object { $_ -match 'ziti-minecraft' }
```

## Reference

[`setup-ziti.ps1`](setup-ziti.ps1) in this repo is the entire controller-side setup as
runnable commands. Identities, service, policies, edge-router policies, enrollment --
all of step 1 through step 4 above in one file. Run it whole, or open it and copy out
the parts you want. The same commands work in bash; only the shell prompt differs.

If you want to dump the full state of your own working controller for diff/audit:

```powershell
ziti ops export | Out-File mine.export.json
```

That produces a much larger file with every controller object plus environment
details (router hostnames, MAC addresses, interface inventories). Sanitize before
sharing publicly.
