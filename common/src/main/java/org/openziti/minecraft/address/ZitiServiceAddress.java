package org.openziti.minecraft.address;

import org.openziti.minecraft.ZitiMc;

public final class ZitiServiceAddress {

    private ZitiServiceAddress() {}

    /**
     * Decide whether a "Server Address" field input should be treated as a Ziti
     * service name rather than a TCP host. Rule: when the mod is enabled, an input
     * with no dot and no colon and no all-digit characters is treated as a Ziti
     * service. Numeric-only inputs are never Ziti. Anything containing {@code .} or
     * {@code :} (IPs, host:port, etc) is never Ziti.
     */
    public static boolean isZitiServiceName(String input) {
        // Client dial is always active when the mod is installed. The serverEnabled
        // toggle only governs the server-side bind, not whether we recognize service
        // names in the "Add Server" address field.
        if (input == null || input.isBlank()) return false;
        if (input.contains(".") || input.contains(":")) return false;
        if (input.chars().allMatch(Character::isDigit)) return false;
        // Reserved hostnames that are never Ziti services, even though they have no
        // dot or colon. Without this, MC's server-list pinger spams the Ziti SDK with
        // dial attempts on every "localhost" entry the user has saved.
        String lower = input.toLowerCase();
        if (lower.equals("localhost") || lower.equals("local") || lower.equals("lan")) return false;
        return true;
    }
}
