package org.openziti.minecraft.address;

import java.net.InetSocketAddress;

/**
 * An {@link InetSocketAddress} that smuggles a Ziti service name through Minecraft's
 * resolution pipeline. The Connection mixin pulls the service name back out at dial time
 * and asks the Ziti SDK to dial it directly, bypassing the TCP host/port the address
 * would otherwise carry.
 *
 * <p>Modeled after e4mc's "SmugglersInetSocketAddress" pattern: extending {@code
 * InetSocketAddress} (rather than introducing a new {@link java.net.SocketAddress}
 * subclass) lets the value flow through method signatures that expect
 * {@code InetSocketAddress} without any further changes.
 */
public final class ZitiSocketAddress extends InetSocketAddress {

    private final String serviceName;

    public ZitiSocketAddress(String serviceName) {
        // Wildcard address, port 0. Never used for a real TCP connect because the
        // Connection mixin substitutes a ZitiAddress.Dial before any socket op runs.
        super(0);
        this.serviceName = serviceName;
    }

    public String getServiceName() {
        return serviceName;
    }

    @Override
    public String toString() {
        return "ZitiSocketAddress[" + serviceName + "]";
    }
}
