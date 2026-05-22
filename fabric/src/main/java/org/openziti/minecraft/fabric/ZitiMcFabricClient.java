package org.openziti.minecraft.fabric;

import net.fabricmc.api.ClientModInitializer;
import org.openziti.minecraft.ZitiMc;

public final class ZitiMcFabricClient implements ClientModInitializer {
    @Override
    public void onInitializeClient() {
        ZitiMc.LOG.info("ziti-minecraft fabric client init");
    }
}
