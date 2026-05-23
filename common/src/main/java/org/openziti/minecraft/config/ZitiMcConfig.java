package org.openziti.minecraft.config;

import me.shedaniel.autoconfig.ConfigData;
import me.shedaniel.autoconfig.annotation.Config;
import me.shedaniel.autoconfig.annotation.ConfigEntry;

/**
 * Cloth Config schema. The annotations drive the auto-generated in-game settings
 * screen reached from ModMenu. AutoConfig handles load/save via Gson; the config file
 * lives at {@code config/openziti.json}.
 *
 * <p>Each field is tagged with a {@code @ConfigEntry.Category} so the screen renders
 * two tabs across the top: <strong>OpenZiti</strong> (today's working backend) and
 * <strong>zrok</strong> (placeholder for v0.3.0).
 *
 * <p>The client-side dial path is always active once the mod is installed. Only the
 * server-side bind is opt-in via {@link #serverEnabled}, because most users are
 * client-only and should not have to think about it.
 */
@Config(name = "openziti")
public final class ZitiMcConfig implements ConfigData {

    // -- OpenZiti tab ----------------------------------------------------

    @ConfigEntry.Category("openziti")
    @ConfigEntry.Gui.Tooltip
    @ConfigEntry.Gui.RequiresRestart
    public String identityPath = "config/openziti/identity.json";

    @ConfigEntry.Category("openziti")
    @ConfigEntry.Gui.PrefixText
    @ConfigEntry.Gui.Tooltip
    @ConfigEntry.Gui.RequiresRestart
    public boolean serverEnabled = false;

    @ConfigEntry.Category("openziti")
    @ConfigEntry.Gui.Tooltip
    @ConfigEntry.Gui.RequiresRestart
    public String serviceName = "openziti-mc";

    // -- zrok tab (placeholder; backend lands in v0.3.0) -----------------

    @ConfigEntry.Category("zrok")
    @ConfigEntry.Gui.PrefixText
    @ConfigEntry.Gui.Tooltip
    public String zrokShareToken = "";
}
