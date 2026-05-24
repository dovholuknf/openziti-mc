package org.openziti.minecraft.config;

import me.shedaniel.autoconfig.ConfigData;
import me.shedaniel.autoconfig.annotation.Config;
import me.shedaniel.autoconfig.annotation.ConfigEntry;

/**
 * Cloth Config schema. The annotations drive the serializer; the actual settings
 * screen is hand-built in {@code ZitiMcModMenu} so we can show diagnostic status.
 *
 * <p>The client-side dial path is always active once the mod is installed. Only the
 * server-side bind is opt-in via {@link #serverEnabled}.
 */
@Config(name = "openziti")
public final class ZitiMcConfig implements ConfigData {

    @ConfigEntry.Gui.Tooltip
    @ConfigEntry.Gui.RequiresRestart
    public String identityPath = "config/openziti/identity.json";

    @ConfigEntry.Gui.Tooltip
    @ConfigEntry.Gui.RequiresRestart
    public boolean serverEnabled = false;

    @ConfigEntry.Gui.Tooltip
    @ConfigEntry.Gui.RequiresRestart
    public String serviceName = "openziti-mc";
}
