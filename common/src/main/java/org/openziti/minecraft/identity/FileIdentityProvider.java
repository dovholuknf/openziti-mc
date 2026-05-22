package org.openziti.minecraft.identity;

import org.openziti.minecraft.ZitiMc;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

/**
 * v1 identity provider. Loads an already-enrolled {@code .json} identity. If the
 * configured path is a {@code .jwt}, enroll it on first use and persist the resulting
 * identity next to the JWT.
 *
 * Behavior is stubbed until the Ziti SDK is wired in. {@link #load()} currently throws
 * if the file is missing and logs a sentinel value otherwise so the rest of the mod
 * can be built and exercised independently.
 */
public final class FileIdentityProvider implements IdentityProvider {

    private final Path path;
    private Object cached;

    public FileIdentityProvider(Path path) {
        this.path = path;
    }

    @Override
    public Object load() throws IOException {
        if (cached != null) {
            return cached;
        }
        if (!Files.exists(path)) {
            throw new IOException("Ziti identity file not found: " + path);
        }
        String name = path.getFileName().toString().toLowerCase();
        if (name.endsWith(".jwt")) {
            cached = enrollJwt();
        } else {
            cached = loadJson();
        }
        return cached;
    }

    private Object loadJson() throws IOException {
        // TODO(zitimc): replace with `Ziti.newContext(path.toFile(), new char[0])`
        // once `org.openziti:ziti` is on the runtime classpath of the loader modules.
        ZitiMc.LOG.info("Would load Ziti identity from {}", path);
        return new Object();
    }

    private Object enrollJwt() throws IOException {
        // TODO(zitimc): call Enroller.fromJWT(...).enroll(...) and persist the result
        // next to `path` with a `.json` extension.
        ZitiMc.LOG.info("Would enroll Ziti JWT at {}", path);
        return new Object();
    }

    @Override
    public String describe() {
        return "file:" + path;
    }
}
