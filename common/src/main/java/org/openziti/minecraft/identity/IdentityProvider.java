package org.openziti.minecraft.identity;

import java.io.IOException;

public interface IdentityProvider {
    /**
     * Load (or enroll-then-load) a Ziti context. Implementations should be idempotent --
     * repeated calls must return the same context, not re-enroll.
     *
     * Return type is {@code Object} until the Ziti SDK is on the compile classpath of
     * downstream callers; loader modules cast to {@code org.openziti.ZitiContext}.
     */
    Object load() throws IOException;

    /** Human-readable label for logs and UI. */
    String describe();
}
