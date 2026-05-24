# OpenZiti MC -- host a server

How to host a Minecraft world over OpenZiti so friends can connect by service
name without you opening a TCP port, getting a public IP, or registering a DNS
name. This complements [INSTALL.md](INSTALL.md) (which covers the client side)
and [SETUP.md](SETUP.md) (which covers controller-side identity + policy
creation).

Tested platform: Windows 11, Mojang launcher, MC 1.20.1 Fabric.

## What "hosting over OpenZiti" actually means

The mod intercepts Netty's `ServerBootstrap.bind(...)` call and, when
`serverEnabled` is on, binds the integrated server on an OpenZiti service
instead of (or alongside) the vanilla TCP listener on port 25565. Only
identities granted **Bind** on that service via service policy can be the
host; only identities granted **Dial** can connect. The OpenZiti edge router
brokers traffic; your home network never sees an inbound connection.

You don't need the dedicated server jar. A regular Minecraft client with this
mod can host via **Pause -> Open to LAN** -- vanilla MC's own button. When
`serverEnabled` is true, the mod intercepts the server-bind path that button
triggers and binds on the configured OpenZiti service instead of (or in
addition to) a TCP port.

## Prerequisites

1. A running OpenZiti controller and at least one edge router. If you don't
   have one, see [SETUP.md](SETUP.md).
2. A **bind** identity for the host machine. Created via:
   ```powershell
   ziti edge create identity mc-host --role-attributes minecraft-server -o mc-host.jwt
   ziti edge enroll --jwt mc-host.jwt -o mc-host.json
   ```
3. A service named `openziti-mc` (or whatever you want to call it) plus matching
   bind / dial service policies keyed on the `#minecraft-server` and
   `#minecraft-clients` role attributes. SETUP.md walks through all of this.
4. The host machine has Fabric Loader for the MC version installed (see
   INSTALL.md Step 2) and the matching OpenZiti MC jar in `<mc-dir>\mods\`.

## Step 1: place the bind identity

Copy `mc-host.json` (or whatever you named it) onto the host machine. **Don't
email it or post it publicly** -- it contains a private key. USB stick,
OneDrive, scp, etc.

```powershell
# Back up any existing identity, then drop the bind identity in place.
$cfg = "$env:APPDATA\.minecraft\config\openziti"
New-Item -ItemType Directory -Force -Path $cfg | Out-Null
if (Test-Path "$cfg\identity.json") {
    $ts = Get-Date -Format "yyyyMMdd-HHmmss"
    Move-Item "$cfg\identity.json" "$cfg\identity.json.bak-$ts"
}
Move-Item C:\path\to\mc-host.json "$cfg\identity.json"
```

If the host runs from a custom game directory (because you have multiple Fabric
profiles on one box -- see below), replace `.minecraft` with that dir name.

## Step 2: flip `serverEnabled` on

The mod ships with `serverEnabled: false` so that adding it to a client install
doesn't accidentally start a listener. For a host, set it to `true` so the
Open-to-OpenZiti path binds:

```powershell
$cfgDir = "$env:APPDATA\.minecraft\config"
$cfg = @{
    identityPath  = "config/openziti/identity.json"
    serverEnabled = $true
    serviceName   = "openziti-mc"
} | ConvertTo-Json
Set-Content -Path "$cfgDir\openziti.json" -Value $cfg -Encoding UTF8
Get-Content "$cfgDir\openziti.json"
```

You can also flip the toggle in-game (**Mods -> OpenZiti MC -> gear**), but the
fields are marked `RequiresRestart`, so you'd need to launch once, change, and
restart.

## Step 3: launch and open the world

1. Open the Mojang launcher, pick the matching `fabric-loader-<mc-version>`
   profile, click Play.
2. **Singleplayer** -> pick a world or create one. Spawn in.
3. Press **Esc** -> click **Open to LAN**.
4. The chat shows the standard "Local game hosted on port ..." message; the
   `openziti-mc.log` shows: `Ziti listener bound on service 'openziti-mc'`.

The vanilla TCP listener is also closed when `serverEnabled=true`, so nothing
is exposed on 25565 -- zero-trust posture by default.

## Step 4: give clients the service name + their identities

Each player needs:
- An enrolled **dial** identity (`#minecraft-clients` role attribute).
- The service name (`openziti-mc` here).
- The client install per [INSTALL.md](INSTALL.md).

They add the server in Multiplayer with **Server Address = `openziti-mc`** (no
port, no protocol). The mod resolves it as a Ziti service via the bundled SDK.

## Verifying access before launching

You can confirm a given identity has the right permissions without launching
Minecraft:

```powershell
ziti edge policy-advisor identities -q mc-host
```

Expected output for a working bind identity:
```
OKAY : mc-host (1) -> openziti-mc (1) Common Routers: (1/1) Dial: N Bind: Y
```

For a dial identity it should show `Dial: Y Bind: N`. If `Common Routers: 0/1`,
the identity-to-edge-router policies are wrong (the identity has no edge router
it can reach).

## Multiple Fabric versions on one host (per-profile game dirs)

If you want multiple Fabric profiles on one machine (e.g. one host for MC
1.20.1 friends, another for 1.21.4), the Mojang launcher's default behavior of
sharing `%APPDATA%\.minecraft\mods\` across all profiles will break things --
the OpenZiti MC jar for 1.20.1 will refuse to load on a 1.21.4 profile.

**Fix**: give each profile its own game dir.

1. Run the Fabric installer once per MC version, leaving **Launcher Location**
   at the default `%APPDATA%\.minecraft` (the installer needs to find
   `launcher_profiles.json` there).
2. In the Mojang launcher, edit each Fabric profile -> **More Options** ->
   **Game directory** -> point at a per-profile path, e.g.
   `%APPDATA%\.minecraft-1.20.1\` and `%APPDATA%\.minecraft-1.21.4\`.
3. Run the installer script with `-ModsDir` and `-ConfigDir` pointing at the
   per-profile path:
   ```powershell
   & $env:TEMP\install-mods.ps1 `
       -MinecraftVersion 1.20.1 `
       -ModsDir "$env:APPDATA\.minecraft-1.20.1\mods" `
       -ConfigDir "$env:APPDATA\.minecraft-1.20.1\config" `
       -IdentityFile C:\path\to\mc-host.json
   ```
4. Now each profile is fully isolated -- different mods, different identity,
   different `openziti.json`, different world saves.

This is the cleanest pattern for development too: keep a `.minecraft-1.20.1\`
that points at the bind identity for testing host flows, and a
`.minecraft-1.21.4\` that points at the dial identity for testing client flows,
all on one box.

## Troubleshooting

| Symptom                                                    | Diagnostic                                                                                                                                                                       |
| ---------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Log says `Ziti listener bound on service 'openziti-mc'`    | Working. Clients can connect.                                                                                                                                                    |
| `Open to LAN` doesn't appear in the pause menu        | `serverEnabled` is `false`. Edit `openziti.json` and relaunch, or flip the toggle in the in-game Mods screen and restart MC.                                                     |
| `policy-advisor` shows `Bind: N`                           | The identity doesn't have the bind role attribute, or the bind service policy doesn't grant that attribute. Re-run `ziti edge update identity ... --role-attributes minecraft-server`. |
| Client gets `Couldn't connect`                             | Run `ziti edge policy-advisor identities -q <client-identity>` -- confirm `Dial: Y` on the service. If `N`, fix the dial policy.                                                 |
| Client connects but disconnects after Login Start          | `online-mode=true` and you're not Mojang-authenticated. For dev testing, edit `server.properties` (or use the integrated server with offline players).                           |
| Multiple players: one connects, others fail                | Each client needs its own enrolled identity. They can't share a single `.json`; the SDK rejects concurrent sessions on the same identity.                                        |
| Client times out at ~30s on a fresh launch                 | The SDK's service catalog hasn't picked up the host's terminator yet. **Start the host first** -- look for `Ziti listener bound on service 'openziti-mc'` in the host's log -- then launch (or relaunch) Minecraft on the client. The SDK refreshes the catalog every ~60s; MC's connect timeout fires after ~30s, so a client that launched before the host has a stale empty catalog. (Tracked: force-refresh on dial is a planned fix.) |

## Logs

Same locations as the client side (see SETUP.md "Finding the logs"). The
host-side line you want is:

```
[ziti-minecraft] Binding Minecraft server to Ziti service 'openziti-mc'
[ziti-minecraft] Ziti listener bound on service 'openziti-mc'
[ziti-minecraft] Closing vanilla TCP listener(s)
```

If you don't see the bind line, check `policy-advisor` first -- the most common
failure is a bind-role-attribute mismatch, not a runtime problem.
