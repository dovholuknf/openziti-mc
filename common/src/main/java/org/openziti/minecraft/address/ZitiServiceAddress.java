package org.openziti.minecraft.address;

import org.openziti.minecraft.ZitiMc;

public final class ZitiServiceAddress {

    private ZitiServiceAddress() {}

    /**
     * Decide whether a "Server Address" field input should be treated as a Ziti
     * service name rather than a TCP host. v1 heuristic:
     *
     * 1. If {@code addressDetection == "prefix"}, only inputs starting with {@code ziti:}
     *    are Ziti services.
     * 2. Otherwise ({@code "implicit"}), an input with no dot and no colon and no port
     *    is treated as a Ziti service. Numeric-only inputs are never Ziti.
     */
    public static boolean isZitiServiceName(String input) {
        if (input == null || input.isBlank()) return false;
        String mode = ZitiMc.config().addressDetection;
        if ("prefix".equalsIgnoreCase(mode)) {
            return input.startsWith("ziti:");
        }
        if (input.contains(".") || input.contains(":")) return false;
        if (input.chars().allMatch(Character::isDigit)) return false;
        return true;
    }

    /** Strip a {@code ziti:} prefix if present. */
    public static String normalize(String input) {
        if (input != null && input.startsWith("ziti:")) {
            return input.substring("ziti:".length());
        }
        return input;
    }
}
