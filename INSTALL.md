# OpenZiti MC -- end-user install

How a real player installs and configures OpenZiti MC on a vanilla Minecraft instance
launched from the Mojang launcher. For controller-side setup (creating the OpenZiti
service and its access policies) see [SETUP.md](SETUP.md); this doc starts at "I'm a
player who wants to join my friend's OpenZiti-hosted server" and ends at "I'm in their
world."

Tested platform: Windows 11, Mojang launcher, Fabric.

## Supported Minecraft versions

Each release ships three jars, one per MC version:

| MC version | Java |
| ---------- | ---- |
| 1.20.1     | 17   |
| 1.21.1     | 21   |
| 1.21.4     | 21   |

Pick whichever your friend's server is on. Mismatched MC + jar will refuse to load.

## Multiple Fabric profiles on one machine

If you already have a Fabric profile for a different MC version, or you want both
1.20.1 and 1.21.4 on the same box, give each profile its own **game directory** so
the mods don't conflict (the OpenZiti MC jar for 1.20.1 will refuse to load on a
1.21.4 profile, and vice versa).

1. Run the Fabric installer once per MC version. Leave the installer's **Launcher
   Location** at the default `%APPDATA%\.minecraft` so it can find
   `launcher_profiles.json`.
2. In the Mojang launcher, edit each profile -> **More Options** -> **Game
   directory** -> point at a per-version path like `%APPDATA%\.minecraft-1.21.4`.
3. Run the install script below with `-ModsDir` and `-ConfigDir` pointing at the
   per-version path:
   ```powershell
   & $env:TEMP\install-mods.ps1 -MinecraftVersion 1.21.4 `
       -ModsDir "$env:APPDATA\.minecraft-1.21.4\mods" `
       -ConfigDir "$env:APPDATA\.minecraft-1.21.4\config"
   ```

The default (single shared `.minecraft\mods\`) works fine if you only ever run one
MC version; the per-profile pattern is only needed when you want multiple.

## Prerequisites

- Minecraft installed via the Mojang launcher (or a launcher-compatible client like
  Modrinth App / Prism / MultiMC).
- The Mojang launcher installs its own Java runtime per MC version, so a separate JDK
  on your PATH is not required for end-user play.
- The OpenZiti **service name** your friend told you to connect to.
- An enrolled OpenZiti identity `.json` file with Dial permission for that service
  (Bind permission too if you're hosting from your own client). The person who set up
  the controller hands you this file or walks you through enrolling.

## Fast path: one-shot installer script (recommended)

If you'd rather not click through Modrinth to download four jars, the repo ships an
installer script that grabs OpenZiti MC plus all required dependencies for you, drops
them in the right folder, and (optionally) places your enrolled identity.

After Fabric Loader is installed (Step 2 below), run this single line in PowerShell:

```powershell
iwr https://raw.githubusercontent.com/dovholuknf/openziti-mc/main/scripts/install-mods.ps1 | iex
```

Press Enter at each prompt to accept the defaults. The script asks for your Minecraft
version (1.20.1, 1.21.1, or 1.21.4) and picks the matching OpenZiti MC jar. When it
asks "Do you have an enrolled OpenZiti identity .json file ready?", answer `y` and
paste the path to your identity file -- the script copies it to the right place. Then
skip ahead to **Step 4: launch and configure**.

The manual steps below remain accurate; use them if you prefer to know exactly which
jars are downloading or if you want pinned versions.

## Step 1: get an enrolled identity .json

This step happens on whichever machine has the `ziti` CLI logged into the controller
(typically the person running the OpenZiti setup, who is hosting or running setup for
the rest of the group). It produces a single file -- `<your-name>.json` -- that gets
copied to the player's machine.

```powershell
# 1. Create a per-device identity tagged with the dial role attribute.
ziti edge create identity clint-laptop --role-attributes minecraft-clients -o clint-laptop.jwt

# 2. Enroll the one-time JWT into a long-lived JSON identity.
ziti edge enroll --jwt clint-laptop.jwt -o clint-laptop.json

# 3. (Optional) Confirm the role attribute attached correctly.
ziti edge list identities 'name="clint-laptop"'
```

The `*.jwt` is single-use and now consumed. The `*.json` is the file the player needs.

**Transfer the `.json` to the player's machine.** USB drive, OneDrive / Dropbox / etc,
scp -- whatever channel you trust. The file contains a private key; do not email it
or post it publicly.

## Step 2: install Fabric Loader on the player's machine

The mod runs on the Fabric mod loader. The official Fabric installer is a one-click
GUI.

1. Download the Windows installer from https://fabricmc.net/use/installer (button:
   **Download installer (Windows)**). You get `fabric-installer-X.Y.Z.exe`.
2. Run it. In the installer window:
   - Tab: **Client**.
   - Minecraft version: **the one matching your OpenZiti MC jar** (1.20.1, 1.21.1, or
     1.21.4). Anything else will refuse to load.
   - Loader version: latest stable. Anything 0.16.x+ for 1.20.1, 0.19.x+ for 1.21.x.
   - Install location: leave the default (auto-detects `.minecraft`).
   - Create profile: checked.
3. Click **Install**, wait for "Successfully installed", close the installer.
4. Verify: open the Mojang launcher, click the **Play** dropdown -- a new profile
   `fabric-loader-<your-mc-version>` should appear. Don't launch it yet.

## Step 3: download and place the mod jars

You need **four** jars in `%APPDATA%\.minecraft\mods\`: OpenZiti MC plus three
dependencies (Fabric API, Cloth Config, ModMenu). Open the mods folder in Explorer
first (paste `%APPDATA%\.minecraft\mods` into the address bar; create the folder if
it does not exist), then download each jar below into that folder.

OpenZiti MC (3a) is published on GitHub Releases and on Modrinth -- either works. The
three dependency mods (3b through 3d) live only on Modrinth.

For each Modrinth download, **filter by your MC version** before picking a file --
each project has separate jars per MC version.

### 3a. OpenZiti MC (the mod itself)

Direct from GitHub Releases:

1. Open https://github.com/dovholuknf/openziti-mc/releases
2. Find the **latest** release at the top.
3. Under **Assets**, click the jar tagged with your MC version, e.g.
   `openziti-mc-0.3.1.mc1.21.4.jar`. The browser downloads it.
4. Move the downloaded file into `%APPDATA%\.minecraft\mods\`.

Or via Modrinth:

1. Open https://modrinth.com/mod/openziti-mc in a browser.
2. Click **Versions**. The list shows separate version rows per MC target.
3. **Filter by your MC version** in the sidebar.
4. Click the row matching your MC, then green **Download** on the version-detail
   page. Save to `%APPDATA%\.minecraft\mods\`.

### 3b. Fabric API (required)

1. Open https://modrinth.com/mod/fabric-api
2. Click **Versions**.
3. Sidebar -> **Game versions** -> click your MC version.
4. Click the top matching row, then **Download** -> move into `mods\`.

### 3c. Cloth Config (required -- powers the in-game settings screen)

1. Open https://modrinth.com/mod/cloth-config
2. Click **Versions**.
3. Sidebar filters: **Game versions** -> your MC version, **Loaders** -> **Fabric**.
4. Click the top matching row, then **Download** -> move into `mods\`.

### 3d. ModMenu (recommended -- surfaces the Configure button in the in-game mod list)

1. Open https://modrinth.com/mod/modmenu
2. Click **Versions**.
3. Sidebar -> **Game versions** -> click your MC version.
4. Click the top matching row, then **Download** -> move into `mods\`.

### Verify

```powershell
ls $env:APPDATA\.minecraft\mods | Select-Object Name, Length
```

You should see four jars. Approximate sizes for sanity:

| Jar prefix             | Size       |
| ---------------------- | ---------- |
| `openziti-mc-*.jar`    | ~28-30 MB  |
| `fabric-api-*.jar`     | ~1-2 MB    |
| `cloth-config-*.jar`   | ~1 MB      |
| `modmenu-*.jar`        | ~750 KB    |

If the OpenZiti MC jar is under 5 MB you grabbed the `-sources.jar` or
`-dev-shadow.jar` by mistake. Re-download the unsuffixed version.

## Step 4: place your identity file

If you used the install script and answered `y` to the identity prompt, this is
already done; skip ahead. Otherwise:

```powershell
# Create the dir if it doesn't exist
New-Item -ItemType Directory -Force -Path $env:APPDATA\.minecraft\config\openziti
# Copy your enrolled .json into place (adjust the source path to wherever you saved it)
Copy-Item C:\path\to\your-identity.json $env:APPDATA\.minecraft\config\openziti\identity.json
```

Verify:

```powershell
ls $env:APPDATA\.minecraft\config\openziti\identity.json
```

The file should be 6-15 KB (a Ziti identity .json).

## Step 5: launch Minecraft and verify the mod loaded

1. Open the Mojang launcher.
2. Click the **Play** dropdown next to the green button and pick the
   **fabric-loader-<your-mc-version>** profile.
3. Click **Play**. Minecraft launches; first launch with new mods takes a bit longer
   while Fabric resolves dependencies.
4. On the main menu, click **Mods** (a button added by ModMenu).
5. Find **OpenZiti MC** in the list. Click the gear icon to its right.
6. The Configure screen opens. Top of the screen shows:
   - **Identity file: FOUND (X KB at <path>)** in green if the identity is correctly
     placed. Red "NOT FOUND" means Step 4 didn't take and you need to fix the path.
   - **Ziti context: Active** in green once the SDK finishes authenticating
     (sometimes you have to wait a few seconds and reopen the screen).
7. Leave **OpenZiti server enabled** off (default) unless you're going to host. The
   **Service name** field is only used for hosting.
8. Close the screen.

## Step 6: join your friend's server

1. Click **Multiplayer** from the main menu.
2. Click **Add Server**.
3. Enter:
   - **Server Name**: anything you want.
   - **Server Address**: the OpenZiti service name your friend gave you (e.g.
     `openziti-mc`). No port. No `https://`. Just the service name.
4. Click **Done**. The server appears in the list with a ping indicator.
5. Wait a few seconds for the first ping; sometimes the first dial after a fresh
   install takes 10-30 seconds while the SDK populates its service catalog.
6. Click the server row, then **Join Server**.

You should see the world load. If anything goes wrong, the **Configure -> Identity
file / Ziti context** status block and `%APPDATA%\.minecraft\logs\openziti-mc.log`
are the first two places to look.

## Common problems

| Symptom                                                  | Fix                                                                                                                                |
| -------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| MC won't launch -- "Incompatible mods" screen on startup | Wrong jar for your MC version. Confirm the jar filename ends `.mc<version>.jar` matching your Fabric profile.                      |
| "Identity file: NOT FOUND" in Configure                  | The `.json` isn't at `config\openziti\identity.json` under the instance dir. Redo Step 4.                                          |
| Connect fails immediately, "Couldn't connect"            | Service name mismatch, or your identity doesn't have Dial permission. Confirm with the host.                                       |
| Connect takes ~30 seconds then fails on first attempt    | SDK catalog warmup. Click Join again -- the second attempt usually succeeds.                                                       |
| Connect succeeds then drops within seconds               | Host's `server.properties` has `online-mode=true`; ask host to set it false for dev testing.                                       |
