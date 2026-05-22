package org.openziti.minecraft.mixin;

import net.minecraft.network.Connection;
import org.spongepowered.asm.mixin.Mixin;

/**
 * Hooks into client {@link Connection#connect} so that when the target address is a
 * Ziti service name, we substitute Netty's {@code NioSocketChannel} +
 * {@code InetSocketAddress} with {@code ZitiChannel} + {@code ZitiAddress.Dial}.
 *
 * Stub: actual Redirects are added in a follow-up commit alongside the Ziti SDK runtime
 * wiring. Keeping this class present and registered so the Mixin config is valid and
 * the loader confirms the target class resolves.
 */
@Mixin(Connection.class)
public abstract class ConnectionMixin {
    // TODO(zitimc):
    //   - @Redirect Bootstrap.channel(Class) when the SocketAddress is a ZitiAddress.Dial
    //   - @ModifyArg / @Redirect on Bootstrap.connect(SocketAddress) to inject ZitiAddress.Dial
}
