package org.openziti.minecraft.config;

import me.shedaniel.autoconfig.ConfigData;
import me.shedaniel.autoconfig.annotation.Config;
import me.shedaniel.autoconfig.annotation.ConfigEntry;

/**
 * Cloth Config schema. The annotations drive the auto-generated in-game settings
 * screen reached from ModMenu. AutoConfig handles load/save via Gson; the config file
 * lives at {@code config/openziti.json}.
 *
 * <p>The client-side dial path is always active once the mod is installed. Only the
 * server-side bind is opt-in via {@link #serverEnabled}, because most users are
 * client-only and should not have to think about it.
 *
 * <p>zrok shares work without any extra config: a zrok environment identity is just
 * an OpenZiti {@code .json} and a zrok share token is just an OpenZiti service name.
 * Point {@link #identityPath} at the zrok env identity and type the share token into
 * "Add Server" -- the dial path is identical.
 */
@Config(name = "openziti")
public final class ZitiMcConfig implements ConfigData {

    @ConfigEntry.Gui.Tooltip
    @ConfigEntry.Gui.RequiresRestart
    public String identityPath = "config/openziti/identity.json";

    @ConfigEntry.Gui.PrefixText
    @ConfigEntry.Gui.Tooltip
    @ConfigEntry.Gui.RequiresRestart
    public boolean serverEnabled = false;

    @ConfigEntry.Gui.Tooltip
    @ConfigEntry.Gui.RequiresRestart
    public String serviceName = "openziti-mc";
}
