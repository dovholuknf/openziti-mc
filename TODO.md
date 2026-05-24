# OpenZiti MC -- TODO

Open work tracked outside of GitHub Issues. Items here are confirmed v0.4.0+
candidates; the actual schedule depends on what shows up in real use.

## UX

- **Service Dial/Bind permission surfacing.** On `ZitiContext.Status.Active`,
  enumerate `ctx.getServices()` and log a line per service like
  `service 'openziti-mc': Dial=true Bind=false`. In the Configure screen, add
  a row for the configured `serviceName` with green / red icons for Dial and
  Bind. Catches the most common permission-mismatch failure before the user
  clicks Join. Refresh on screen-open, don't cache.

- **Log-level dropdown in Configure.** Expose TRACE / DEBUG / INFO / WARN /
  ERROR in the in-game settings screen. Apply via Log4j2 `Configurator.setLevel`
  to the `org.openziti.minecraft` package and the `org.openziti.*` SDK loggers.
  No restart needed. Default INFO. Today the only way to get DEBUG is to
  recompile.

## Reliability

- **Force service-catalog refresh on dial.** When a client clicks Connect, ask
  the SDK to refresh the catalog instead of waiting for its ~60s poll. Today,
  if the client launched before the host's terminator existed, the cached
  catalog is empty and MC's 30s connect timeout fires before the next SDK
  poll, so the first dial after a fresh start fails even when policy and
  routing are fine. Workaround: relaunch the client after the host is up.

- **In-process JWT enrollment.** `FileIdentityProvider` currently expects an
  already-enrolled `.json`. If the user provides a `.jwt`, enroll it in
  process via the Ziti SDK, write the resulting `.json` to the same path, log
  the new identity name, and continue. JWTs are single-use; rename the source
  to `.jwt.consumed` after a successful enroll. Once this lands,
  `install-mods.ps1` can accept either a `.jwt` or `.json` via
  `-IdentityFile` without caring which -- it just copies the file across and
  the mod handles the rest on first launch. Today the user has to run
  `ziti edge enroll` manually before launching MC.

## MC version coverage

- **Re-enable mc-1.21.11.** v0.4.0 bumped Loom to 1.11.x and Gradle to 8.14,
  which unblocked `mc-1.21.5` through `mc-1.21.10`. `mc-1.21.11` still trips
  Loom's check that mods ship javadoc with an intermediary source namespace
  -- fabric-api 0.141.4+1.21.11 doesn't. Retry when either Loom relaxes the
  check or fabric-api ships a fixed source artifact for 1.21.11.

## Polish

- **Silence LAN broadcast on the host.** When `serverEnabled=true`, MC still
  emits the `[MOTD]` multicast packet to `224.0.2.60:4445` every ~1.5s so
  nearby clients see the world under "Scanning for games on your local
  network". Harmless but noisy. A Mixin to skip the broadcast when running
  Ziti-only would clean this up.

## Done (for context)

See git history for v0.1.x -> v0.3.2. Highlights:
- v0.3.2: 12 MC version targets, HOSTING.md, doc patches.
- v0.3.1: jar names use `.mc` separator (GitHub Releases sanitize `+`).
- v0.3.0: multi-version Fabric (1.20.1 / 1.21.1 / 1.21.4), drop Architectury.
- v0.2.3: UI polish, INSTALL.md.
- v0.2.0: in-game Cloth Config + ModMenu UI, GH Actions release workflow.
- v0.1.0: initial Mixin-based dial + bind on MC 1.20.1.
