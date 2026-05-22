package org.openziti.minecraft.mixin;

import net.minecraft.server.network.ServerConnectionListener;
import org.spongepowered.asm.mixin.Mixin;

/**
 * Hooks the dedicated/integrated server's TCP listener so we can additionally bind on
 * a Ziti service when {@code serverBind.enabled} is true in the config.
 *
 * Stub: actual hooks added in a follow-up commit. e4mc's ServerConnectionListenerMixin
 * is the reference for the @ModifyArg / @Inject(TAIL) pattern.
 */
@Mixin(ServerConnectionListener.class)
public abstract class ServerConnectionListenerMixin {
    // TODO(zitimc):
    //   - capture EventLoopGroup / ChannelHandler via @ModifyArg on startTcpServerListener
    //   - @Inject(at=TAIL) to construct a ZitiServerChannel and bind to a ZitiAddress.Bind
    //   - @Inject(at=HEAD) on stop() to gracefully close the Ziti listener
}
