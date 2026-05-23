package org.openziti.minecraft.fabric;

import com.terraformersmc.modmenu.api.ConfigScreenFactory;
import com.terraformersmc.modmenu.api.ModMenuApi;
import me.shedaniel.autoconfig.AutoConfig;
import org.openziti.minecraft.config.ZitiMcConfig;

/**
 * Surfaces a "Configure" button in the in-game Mods list (via ModMenu) that opens the
 * Cloth Config screen auto-generated from the {@link ZitiMcConfig} schema.
 */
public final class ZitiMcModMenu implements ModMenuApi {
    @Override
    public ConfigScreenFactory<?> getModConfigScreenFactory() {
        return parent -> AutoConfig.getConfigScreen(ZitiMcConfig.class, parent).get();
    }
}
