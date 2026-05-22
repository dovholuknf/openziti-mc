package org.openziti.minecraft;

import org.openziti.minecraft.config.ZitiMcConfig;
import org.openziti.minecraft.identity.FileIdentityProvider;
import org.openziti.minecraft.identity.IdentityProvider;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.nio.file.Path;
import java.nio.file.Paths;

public final class ZitiMc {
    public static final String MOD_ID = "openziti";
    public static final Logger LOG = LoggerFactory.getLogger("ziti-minecraft");

    private static ZitiMcConfig CONFIG;
    private static IdentityProvider IDENTITY;

    private ZitiMc() {}

    public static void init() {
        Path configDir = Paths.get("config");
        CONFIG = ZitiMcConfig.loadOrCreate(configDir.resolve(MOD_ID + ".json"));
        IDENTITY = new FileIdentityProvider(Paths.get(CONFIG.identityPath));
        LOG.info("ziti-minecraft init: identity provider = {}", IDENTITY.describe());
    }

    public static ZitiMcConfig config() {
        return CONFIG;
    }

    public static IdentityProvider identity() {
        return IDENTITY;
    }
}
