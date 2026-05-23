package org.openziti.minecraft.identity;

import org.openziti.Ziti;
import org.openziti.ZitiContext;
import org.openziti.minecraft.ZitiMc;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

/**
 * v1 identity provider. Loads an already-enrolled {@code .json} identity via
 * {@link Ziti#newContext(java.io.File, char[])}.
 *
 * <p>If the configured path is a {@code .jwt}, emits a friendly error pointing the user
 * at the {@code ziti edge enroll} CLI rather than attempting in-process enrollment.
 * In-process enrollment is out of scope for v1 -- it requires keystore management that
 * isn't worth the surface area until a real user asks for it.
 */
public final class FileIdentityProvider implements IdentityProvider {

    private final Path path;
    private volatile ZitiContext cached;

    public FileIdentityProvider(Path path) {
        this.path = path;
    }

    @Override
    public ZitiContext load() throws IOException {
        ZitiContext ctx = cached;
        if (ctx != null) return ctx;
        synchronized (this) {
            if (cached != null) return cached;
            if (!Files.exists(path)) {
                throw new IOException("Ziti identity file not found: " + path
                    + " (set 'identityPath' in config/" + ZitiMc.MOD_ID + ".json)");
            }
            String name = path.getFileName().toString().toLowerCase();
            if (name.endsWith(".jwt")) {
                throw new IOException("In-process JWT enrollment is not supported in v1. "
                    + "Run `ziti edge enroll --jwt " + path + "` to produce a .json "
                    + "identity, then point 'identityPath' at it.");
            }
            ZitiMc.LOG.info("Loading Ziti identity from {}", path);
            cached = Ziti.newContext(path.toFile(), new char[0]);
            return cached;
        }
    }

    @Override
    public String describe() {
        return "file:" + path;
    }
}
