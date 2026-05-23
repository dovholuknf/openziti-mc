package org.openziti.minecraft.identity;

import org.openziti.ZitiContext;

import java.io.IOException;

public interface IdentityProvider {
    /**
     * Load (or enroll-then-load) a Ziti context. Implementations must be idempotent --
     * repeated calls return the same context, not re-enroll.
     */
    ZitiContext load() throws IOException;

    /** Human-readable label for logs and UI. */
    String describe();
}
