package org.openziti.minecraft.mixin;

import net.minecraft.client.multiplayer.resolver.ServerAddress;
import org.spongepowered.asm.mixin.Mixin;

/**
 * Lets {@link ServerAddress#parseString} accept Ziti service name inputs by skipping
 * the host:port parser and synthesizing a ServerAddress whose host is the raw service
 * name. The downstream Connection mixin reads this back when deciding how to dial.
 *
 * Stub: behavior added in a follow-up commit.
 */
@Mixin(ServerAddress.class)
public abstract class ServerAddressMixin {
    // TODO(zitimc):
    //   - @Inject(at=HEAD, cancellable=true) on parseString(String):
    //       if ZitiServiceAddress.isZitiServiceName(input):
    //           cir.setReturnValue(new ServerAddress(ZitiServiceAddress.normalize(input), 0));
}
