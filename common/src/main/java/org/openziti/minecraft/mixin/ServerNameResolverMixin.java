package org.openziti.minecraft.mixin;

import net.minecraft.client.multiplayer.resolver.ResolvedServerAddress;
import net.minecraft.client.multiplayer.resolver.ServerAddress;
import net.minecraft.client.multiplayer.resolver.ServerNameResolver;
import org.openziti.minecraft.ZitiMc;
import org.openziti.minecraft.address.ZitiServiceAddress;
import org.openziti.minecraft.address.ZitiSocketAddress;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

import java.net.InetSocketAddress;
import java.util.Optional;

/**
 * Short-circuits MC's name resolution for Ziti service names. When the user types a
 * Ziti service in the server-address field, this mixin returns a {@code
 * ResolvedServerAddress} wrapping a {@link ZitiSocketAddress} instead of going through
 * JNDI/SRV/DNS. The Connection mixin then recognizes the smuggled address and dials
 * via the Ziti SDK.
 */
@Mixin(ServerNameResolver.class)
public abstract class ServerNameResolverMixin {

    @Inject(method = "resolveAddress", at = @At("HEAD"), cancellable = true)
    private void zitimc$resolveAsZitiService(
            ServerAddress address,
            CallbackInfoReturnable<Optional<ResolvedServerAddress>> cir) {
        String host = address.getHost();
        if (!ZitiServiceAddress.isZitiServiceName(host)) return;
        String service = ZitiServiceAddress.normalize(host);
        ZitiMc.LOG.info("Resolving '{}' as Ziti service", service);
        cir.setReturnValue(Optional.of(new ResolvedServerAddress() {
            @Override public String getHostName() { return service; }
            @Override public String getHostIp() { return "127.0.0.1"; }
            @Override public int getPort() { return 0; }
            @Override public InetSocketAddress asInetSocketAddress() {
                return new ZitiSocketAddress(service);
            }
        }));
    }
}
