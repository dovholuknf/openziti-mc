# OpenZiti MC -- end-user install

How a real player installs and configures OpenZiti MC on a vanilla Minecraft instance
launched from the Mojang launcher. For controller-side setup (creating the OpenZiti
service and its access policies) see [SETUP.md](SETUP.md); this doc starts at "I'm a
player who wants to join my friend's OpenZiti-hosted server" and ends at "I'm in their
world."

Tested platform: Windows 11, Mojang launcher, MC 1.20.1 Fabric.

## Prerequisites

- Minecraft installed via the Mojang launcher (or a launcher-compatible client like
  Modrinth App / Prism / MultiMC).
- Java 17 -- the Mojang launcher installs its own Java runtime for MC 1.20.1, so a
  separate JDK on your PATH is not required for end-user play.
- The OpenZiti **service name** your friend told you to connect to.
- An enrolled OpenZiti identity `.json` file with Dial permission for that service
  (Bind permission too if you're hosting from your own client). The person who set up
  the controller hands you this file or walks you through enrolling.

## Fast path: one-shot installer script (recommended)

If you'd rather not click through Modrinth to download five jars, the repo ships an
installer script that grabs OpenZiti MC and all four required dependencies for you,
drops them in the right folder, and (optionally) places your enrolled identity.

After Fabric Loader is installed (Step 2 below), run this single line in PowerShell:

```powershell
iwr https://raw.githubusercontent.com/dovholuknf/openziti-mc/main/scripts/install-mods.ps1 | iex
```

Press Enter at each prompt to accept the defaults. When it asks "Do you have an
enrolled OpenZiti identity .json file ready?", answer `y` and paste the path to your
identity file -- the script copies it to the right place. Then skip ahead to **Step
4: launch and configure**.

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
   - Minecraft version: **1.20.1** (the mod is pinned to 1.20.1; anything else will
     refuse to load).
   - Loader version: latest stable (0.19.x at time of writing; anything 0.16.10+ is
     fine).
   - Install location: leave the default (auto-detects `.minecraft`).
   - Create profile: checked.
3. Click **Install**, wait for "Successfully installed", close the installer.
4. Verify: open the Mojang launcher, click the **Play** dropdown -- a new profile
   `fabric-loader-1.20.1` should appear. Don't launch it yet.

## Step 3: download and place the mod jars

You need **five** jars in `%APPDATA%\.minecraft\mods\`: OpenZiti MC plus four
dependencies. Open the mods folder in Explorer first (paste `%APPDATA%\.minecraft\mods`
into the address bar; create the folder if it does not exist), then download each jar
below straight into that folder.

OpenZiti MC (3a) is published on GitHub Releases and on Modrinth -- either works. The
four dependency mods (3b through 3e) live only on Modrinth.

### 3a. OpenZiti MC (the mod itself)

Two sources. GitHub Releases is canonical and always available. Modrinth shows the
same jar but lists go through moderator review after each upload, so for early
versions the Modrinth listing may not be public yet -- if the page 404s or only shows
"Pending review", use the GitHub path instead.

Direct from GitHub Releases:

1. Open https://github.com/dovholuknf/openziti-mc/releases
2. Find the **latest** release at the top (currently v0.2.3 or higher).
3. Under **Assets**, click `openziti-fabric-<version>.jar`. The browser downloads it.
4. Move the downloaded file from your Downloads folder into
   `%APPDATA%\.minecraft\mods\`.

Or via Modrinth:

1. Open https://modrinth.com/mod/openziti-mc in a browser.
2. Under the project title, find the row of tabs: **Description / Gallery / Changelog /
   Versions**. Click **Versions**.
3. The latest version is at the top of the list. Click the row to open the
   version-detail page.
4. On the version-detail page, click the green **Download** button at the top, or the
   download-arrow icon next to the `openziti-fabric-<version>.jar` file in the
   **Files** section.
5. The browser saves the jar to your Downloads folder.
6. Move the file from Downloads into `%APPDATA%\.minecraft\mods\`. Easiest way: open a
   second Explorer window, paste `%APPDATA%\.minecraft\mods` into the address bar, hit
   Enter, then drag the jar across.

### 3b. Fabric API (required)

1. Open https://modrinth.com/mod/fabric-api
2. Click **Versions**.
3. In the left sidebar, find the **Game versions** filter and click **1.20.1**. The
   list narrows to 1.20.1-compatible releases.
4. Click the top matching row (filename will look like `fabric-api-0.92.5+1.20.1.jar`
   or similar -- pick the highest-numbered one).
5. Click the green **Download** button on the version detail page.
6. Move the file into `%APPDATA%\.minecraft\mods\`.

### 3c. Architectury API (required)

1. Open https://modrinth.com/mod/architectury-api
2. Click **Versions**.
3. Sidebar -> **Game versions** -> click **1.20.1**.
4. Sidebar -> **Loaders** -> click **Fabric**. (Architectury also publishes NeoForge
   builds; we explicitly want the Fabric one.)
5. Click the top matching row (around `architectury-9.2.x-fabric.jar`).
6. Click **Download** -> move into `mods\`.

### 3d. Cloth Config (required -- powers the in-game settings screen)

1. Open https://modrinth.com/mod/cloth-config
2. Click **Versions**.
3. Sidebar filters: **Game versions** -> **1.20.1**, **Loaders** -> **Fabric**.
4. Click the top matching row (around `cloth-config-11.1.x-fabric.jar`).
5. **Download** -> move into `mods\`.

### 3e. ModMenu (recommended -- surfaces the Configure button in the in-game mod list)

1. Open https://modrinth.com/mod/modmenu
2. Click **Versions**.
3. Sidebar -> **Game versions** -> click **1.20.1**.
4. Click the top matching row (around `modmenu-7.2.x.jar`).
5. **Download** -> move into `mods\`.

### Verify

```powershell
ls $env:APPDATA\.minecraft\mods | Select-Object Name, Length
```

You should see five jars. Approximate sizes for a sanity check:

| Jar                              | Size  |
| -------------------------------- | ----- |
| `openziti-fabric-0.2.0.jar`      | ~28 MB |
| `fabric-api-0.92.X+1.20.1.jar`   | ~2 MB  |
| `architectury-9.2.X-fabric.jar`  | ~700 KB |
| `cloth-config-11.1.X-fabric.jar` | ~1 MB  |
| `modmenu-7.2.X.jar`              | ~750 KB |

If a jar is missing or the OpenZiti MC one is < 5 MB, something went wrong (the small
"sources" jar or "dev-shadow" jar can land instead of the proper one). Re-download the
file matching the expected size.

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
   **fabric-loader-1.20.1** profile.
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

| Symptom                                                  | Fix                                                                                            |
| -------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| MC won't launch -- "Incompatible mods" screen on startup | Wrong Fabric Loader version. Re-run the Fabric installer and pick 1.20.1; loader 0.16.10+.     |
| "Identity file: NOT FOUND" in Configure                  | The `.json` isn't at `config\openziti\identity.json` under the instance dir. Redo Step 4.       |
| Connect fails immediately, "Couldn't connect"            | Service name mismatch, or your identity doesn't have Dial permission. Confirm with the host.   |
| Connect takes ~30 seconds then fails on first attempt    | SDK catalog warmup. Click Join again -- the second attempt usually succeeds.                   |
| Connect succeeds then drops within seconds               | Host's `server.properties` has `online-mode=true`; ask host to set it false for dev testing.   |
