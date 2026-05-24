package org.openziti.minecraft;

import me.shedaniel.autoconfig.AutoConfig;
import me.shedaniel.autoconfig.ConfigHolder;
import me.shedaniel.autoconfig.serializer.GsonConfigSerializer;
import org.openziti.ZitiContext;
import org.openziti.minecraft.config.ZitiMcConfig;
import org.openziti.minecraft.identity.FileIdentityProvider;
import org.openziti.minecraft.identity.IdentityProvider;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.nio.file.Paths;
import java.util.concurrent.TimeUnit;

public final class ZitiMc {
    public static final String MOD_ID = "openziti";
    public static final Logger LOG = LoggerFactory.getLogger("ziti-minecraft");

    /** How long to wait for the Ziti context to reach Active on first load. */
    private static final long WARMUP_TIMEOUT_NANOS = TimeUnit.SECONDS.toNanos(15);

    private static ConfigHolder<ZitiMcConfig> CONFIG_HOLDER;
    private static IdentityProvider IDENTITY;
    private static volatile ZitiContext ZITI_CONTEXT;

    private ZitiMc() {}

    public static void init() {
        LogSetup.attachFileAppender();
        CONFIG_HOLDER = AutoConfig.register(ZitiMcConfig.class, GsonConfigSerializer::new);
        ZitiMcConfig cfg = CONFIG_HOLDER.getConfig();
        IDENTITY = new FileIdentityProvider(Paths.get(cfg.identityPath));
        LOG.info("ziti-minecraft init: identity provider = {} (mod log also at logs/openziti-mc.log)", IDENTITY.describe());

        // Eagerly warm the Ziti context in a daemon thread so the first dial (typically
        // the server-list pinger right after the multiplayer screen opens) doesn't race
        // the SDK's controller authentication + service catalog sync. Failures here
        // are non-fatal -- if no identity is configured the actual dial path will log
        // and fail later, but the mod itself stays loaded.
        Thread warmUp = new Thread(() -> {
            try {
                zitiContext();
                LOG.info("Ziti context warm-up complete");
            } catch (Throwable t) {
                LOG.warn("Ziti context warm-up failed (OK if no identity configured): {}", t.getMessage());
            }
        }, "ziti-warmup");
        warmUp.setDaemon(true);
        warmUp.start();
    }

    public static ZitiMcConfig config() {
        return CONFIG_HOLDER.getConfig();
    }

    public static IdentityProvider identity() {
        return IDENTITY;
    }

    /**
     * Lazy-loads the {@link ZitiContext} on first call and blocks until the SDK reports
     * {@code Status.Active} (or hits a terminal failure state, or times out). Without
     * this wait, the very first dial races the SDK's async controller auth + service
     * fetch and fails with {@code ServiceNotAvailable}.
     */
    public static ZitiContext zitiContext() {
        ZitiContext ctx = ZITI_CONTEXT;
        if (ctx != null) return ctx;
        synchronized (ZitiMc.class) {
            if (ZITI_CONTEXT != null) return ZITI_CONTEXT;
            try {
                ZitiContext loaded = IDENTITY.load();
                waitForActive(loaded);
                ZITI_CONTEXT = loaded;
            } catch (IOException ioe) {
                LOG.error("Failed to load Ziti identity from {}", IDENTITY.describe(), ioe);
                throw new RuntimeException("Ziti identity not available: " + ioe.getMessage(), ioe);
            }
            return ZITI_CONTEXT;
        }
    }

    private static void waitForActive(ZitiContext ctx) {
        long deadline = System.nanoTime() + WARMUP_TIMEOUT_NANOS;
        while (System.nanoTime() < deadline) {
            ZitiContext.Status status = ctx.getStatus();
            if (status instanceof ZitiContext.Status.Active) {
                LOG.info("Ziti context active");
                return;
            }
            if (status instanceof ZitiContext.Status.NotAuthorized
                    || status instanceof ZitiContext.Status.Unavailable
                    || status instanceof ZitiContext.Status.Disabled) {
                throw new RuntimeException("Ziti context terminal state: " + status);
            }
            try {
                Thread.sleep(100);
            } catch (InterruptedException ie) {
                Thread.currentThread().interrupt();
                return;
            }
        }
        LOG.warn("Ziti context did not reach Active within 15s; current status={}, dials may fail",
            ctx.getStatus());
    }
}
