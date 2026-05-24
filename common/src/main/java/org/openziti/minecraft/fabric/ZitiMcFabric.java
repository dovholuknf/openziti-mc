package org.openziti.minecraft.fabric;

import net.fabricmc.api.ModInitializer;
import org.openziti.minecraft.ZitiMc;

public final class ZitiMcFabric implements ModInitializer {
    @Override
    public void onInitialize() {
        ZitiMc.init();
    }
}
