# zrok integration / a zrok-mc sibling -- planning notes

Captured 2026-05-23 while waiting for the openziti-mc v0.1.0 release to finish on CI.
Goal: decide how (and whether) to ship a zrok variant of this mod.

## Verdict (2026-05-23 evening, after the live test)

**Reverted.** Plain OpenZiti without zrok is what ships. Captured below so we can pick
up the thread if zrok gets smoother in the future.

### What we proved works

zrok was used as a provisioning UX layer on top of OpenZiti. Pure-mod flow at runtime:

1. **Host.** `zrok2 create share --backend-mode tcpTunnel --share-token openziti-mc`
   pre-allocates a private share. Zrok's underlying controller creates an OpenZiti
   service named `openziti-mc` plus a Bind policy granting the host's zrok env
   identity authorization to bind. No `zrok2 share` runtime process needed.
2. **Mod (host).** Loads the zrok env identity (copied from
   `~/.zrok2/identities/environment.json`), and with `serverMode=OPENZITI` +
   `serviceName=openziti-mc` the existing `ServerConnectionListenerMixin` binds on
   that service via the OpenZiti JVM SDK -- identical code path to direct OpenZiti
   hosting.
3. **Host -> client access.** `zrok2 modify share openziti-mc --add-access-grant
   <client-account-email>` whitelists the client account.
4. **Client.** `zrok2 access private openziti-mc --headless` claims the access for
   the client env (creates the Dial policy on OpenZiti's controller side).
5. **Mod (client).** Loads the client zrok env identity, types `openziti-mc` into
   "Add Server," dials via the existing `ConnectionMixin` path. Works.

So the architectural finding from the original plan was correct: a zrok share token
is just an OpenZiti service name and a zrok env identity is just an OpenZiti `.json`.
The mod needs no zrok-specific code paths at runtime.

### Why we reverted

Real-world friction outweighed the "no controller to run" win for our use case:

1. **zrok v2 dropped `reserve`** and reorganized the CLI. The flow we'd want to
   document in user-facing setup steps now involves `create share` + `modify share`
   + `access private --headless`. That's three subcommands users have to know about,
   each with its own flags, none of which are obvious from `zrok2 --help`.

2. **Access grants are per-env, not per-account.** Even when host and client are
   under the same zrok account, the client env doesn't automatically have access to
   the host's shares. We tried `--add-access-grant <our-own-email>`; still failed.
   The fix was the explicit `zrok2 access private` claim on the client side. That's
   a sharp edge for first-time users.

3. **First-connect latency was painful.** After granting access, the client's
   OpenZiti SDK doesn't know about the new service until its next `/service-updates`
   poll. The poll runs once a minute or so. So between "I clicked Join Server" and
   "I'm in the world" can be 2-3 minutes on the first attempt. Subsequent attempts
   are instant. v0.2.1's 30-second catalog wait is too short for this case; bumping
   to 3 minutes would mask the latency but block the MC client on a real failure
   for 3 minutes too. There's no SDK API to force-refresh the catalog.

4. **Another binary to install.** zrok2 CLI is required for setup (one-time on host
   and client). That's the same friction zrok was supposed to remove versus running
   your own OpenZiti controller -- now the user installs zrok2 on every machine
   instead of an OpenZiti CLI on one machine.

The trade was supposed to be "no controller in exchange for one extra binary." In
practice it's "no controller, extra binary, three opaque subcommands, three-minute
first-connect, one access-grant gotcha." Direct OpenZiti remains the cleaner story
for our specific use case.

### What stays in the repo from this experiment

- `serverMode` enum stays as a boolean (`serverEnabled`) again -- the
  `EXTERNAL_TUNNELER` value only existed to flag "zrok is doing the binding," which
  we are no longer pretending to support.
- SETUP.md "Bonus: use a zrok share token" section was deleted to avoid pointing
  users at a flow we don't actively support.
- Identity backups (`identity.server-mc.json.bak` etc.) were already cleaned up
  locally during the revert.

### If we ever come back to this

The pure-mod-runtime story (zrok for provisioning only) is sound. What would need
to be solved:

- A way to force the OpenZiti SDK to refresh its catalog on demand, so the
  first-connect latency disappears. Worth filing as an SDK feature request.
- A simpler user-facing recipe -- maybe a `scripts/zrok-setup.ps1` that wraps all
  the zrok2 incantations into one interactive run.
- An "open share" mode (`--open`) so the user doesn't need to think about access
  grants. Sacrifices the zero-trust posture but is honest about what an MC mod
  user expects.

## The product question

OpenZiti and zrok are the same underlying technology with different ergonomics:

| | openziti-mc (today) | zrok variant |
| --- | --- | --- |
| Audience | Enterprise / zero-trust | Casual friend-sharing |
| Setup overhead | Self-host controller + edge router | None, just `zrok enable` |
| Auth model | Per-identity (enrolled `.json`) | Per-share-token (one string) |
| Network path | Direct via overlay routers | Through zrok frontend (public or self-hosted) |
| Friend's setup | Install mod + receive identity | Receive share token, paste it |

The Netty hook trick underneath is identical. The differences live in the identity
loader, the channel factory, and the config schema.

## The structural choice

Three viable shapes:

1. **Separate sibling project (`zrok-mc`).** New repo, new Modrinth listing, new
   display name "zrok MC". Cross-link from each Modrinth page. Most clarity for users
   ("pick the one that matches your situation"), most duplication of scaffolding.

2. **One mod, two backends, picked in config.** Same jar, `mode = openziti | zrok`.
   Less clarity in marketing ("what does this mod do?"), most shared code.

3. **One mod, two backends, picked via in-game UI.** Same jar as (2) but the user
   chooses the backend in a Cloth Config / ModMenu settings screen rather than
   hand-editing JSON. New audience: players who would never edit a config file but
   will click a dropdown. This option came up after considering the UI angle (see
   below) and is the most interesting if the UI work is in scope.

## What openziti-mc and a zrok variant would share

- The smuggler `InetSocketAddress` pattern
- `ServerNameResolverMixin` shape
- `ConnectionMixin` `@Redirect` shape (different concrete channel factory, same flow)
- `ServerConnectionListenerMixin` `@ModifyArg` capture pattern
- Architectury scaffolding, gradle build setup, fabric.mod.json shape
- The `disableTcp` zero-trust posture switch

What changes:

- **Identity / share-token loader.** `IdentityProvider` interface is already pluggable.
  Add `FileIdentityProvider` (today) + `ZrokShareProvider` (new).
- **Channel implementation.** `ZitiChannelFactory` vs `ZrokShareChannelFactory`. The
  zrok JVM story needs research -- is there a `zrok-sdk-jvm`, or do we shell out to
  the `zrok` CLI as a subprocess?
- **Config schema.** Mode-discriminated.

## v1 shipping options

**Cheapest: server-side-only zrok-mc.** Bind the dedicated server as a zrok private
share at startup, output the share token to the log. Friends use vanilla `zrok access
private <token> tcp <localport>` on their machine, then connect MC to
`localhost:<localport>`. No client mod required. Server-side mod only.

**Full parity: client + server zrok-mc.** Mod handles both the share (server) and the
access tunnel (client) in-process. Requires either a JVM zrok SDK or subprocess
control of the `zrok` CLI.

## Open research

1. **Is there a maintained `zrok-sdk-jvm`?** Determines whether in-process zrok is
   realistic or if we shell out.
2. **zrok reserved shares.** Are stable tokens cheap (free, self-serve), or paid-only?
   Drives whether the user workflow is "regenerate token each play session" or
   "save the stable token in your config."
3. **Public zrok frontend throughput / latency.** Is `zrok.io` viable for real-time
   game traffic, or do users need to run their own zrok-controller? If the latter,
   we're back at OpenZiti-tier complexity and the zrok value prop weakens.

## The UI angle (added late, but reframes the decision)

Minecraft mods can absolutely ship in-game UIs. The standard Fabric pattern is
[Cloth Config](https://github.com/shedaniel/cloth-config) + [ModMenu](https://github.com/TerraformersMC/ModMenu):
declare a typed config schema in code, library auto-generates a settings screen with
the right widget for each field, ModMenu surfaces a "Configure" button in the in-game
Mods list.

What a UI buys us:

- **Audience expansion.** Players who would never hand-edit `config/openziti.json`
  will happily click a dropdown that says "Use zrok (easy) / Use OpenZiti (advanced)."
- **Wizard-style setup.** "First run? Paste your share token here -> Done." Hides the
  complexity entirely for the casual case.
- **In-game JWT enrollment.** Task #18 (in-process enrollment) becomes a button
  instead of a CLI step.
- **Status indicators.** "Overlay status: Connected." "Identity: client-mc." Visible
  feedback when something is wrong.

What a UI costs us:

- Cloth Config + ModMenu add ~2 MB of dependencies (not huge given we already bundle
  the Ziti SDK).
- Schema migration: today's `ZitiMcConfig` POJO works with Gson directly. Cloth
  Config wants annotations or a builder API. Migration is mechanical but real.
- "Custom screens" beyond Cloth Config (real wizard flows, dialog boxes) require
  hand-rolled `Screen` subclasses against vanilla's API. Larger lift.

## Recommendation

If we ship a UI, **option 3 becomes the right choice**: one mod, two backends, picked
in-game. The dropdown ("openziti | zrok | off") is the single most user-facing
decision and it lives next to the per-backend config in the same settings screen.
This is the version that meaningfully helps users who do not know what they are
doing.

If we do not ship a UI, **option 1** (separate sibling project) is better. The
in-config "mode" toggle in option 2 has all the cost of two backends with none of the
UX payoff, and the marketing story is muddled.

So the meta-decision is: do we want to invest in a UI?

## Next steps if we go UI-route

1. Add Cloth Config + ModMenu as dependencies in `fabric/build.gradle`.
2. Convert `ZitiMcConfig` into a Cloth Config schema. Keep Gson serialization for
   backwards-compat with existing `config/openziti.json` files.
3. Add a top-level `connectionMode` enum: `OpenZiti | Zrok | Disabled`.
4. Group existing settings under an "OpenZiti" tab.
5. Add a "zrok" tab with placeholder fields (share token, frontend URL). Wire up the
   actual zrok backend later.
6. Ship a v0.2.0 with the UI scaffolded but only OpenZiti backend wired; zrok wired
   in v0.3.0 once the SDK question is resolved.
7. Rename the mod's display name on Modrinth from "OpenZiti MC" to something
   backend-neutral like "Overlay MC" or "Private MC" -- because the listing now
   covers both modes.

## Next steps if we ship a sibling project instead

1. New repo `dovholuknf/zrok-mc`. Clone the scaffolding from openziti-mc.
2. Replace `org.openziti:ziti-netty` with the zrok equivalent (depending on what
   exists).
3. New Modrinth project `zrok-mc`, display name "zrok MC". Description hits the
   casual / friend-sharing value prop.
4. Cross-link from openziti-mc's Modrinth description ("doing enterprise zero-trust?
   you're in the right place. Just sharing with friends? See zrok-mc.").
