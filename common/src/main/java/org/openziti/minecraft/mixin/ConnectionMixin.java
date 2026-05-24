package org.openziti.minecraft.mixin;

import io.netty.bootstrap.AbstractBootstrap;
import io.netty.bootstrap.Bootstrap;
import io.netty.channel.ChannelFuture;
import net.minecraft.network.Connection;
import org.openziti.ZitiAddress;
import org.openziti.minecraft.ZitiMc;
import org.openziti.minecraft.address.ZitiSocketAddress;
import org.openziti.netty.ZitiChannelFactory;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.Redirect;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.util.concurrent.TimeUnit;

/**
 * Substitutes Netty's NIO/Epoll socket channel and TCP connect with a Ziti channel and
 * a {@link ZitiAddress.Dial} when the destination is a {@link ZitiSocketAddress}.
 *
 * <p>Flow: {@link ServerNameResolverMixin} returns a {@code ZitiSocketAddress} for a
 * Ziti service name. {@link Connection#connect} receives it. We tag the call via a
 * thread-local, then redirect the two Netty bootstrap calls that build the channel and
 * initiate the connect.
 */
@Mixin(Connection.class)
public abstract class ConnectionMixin {

    @Unique
    private static final ThreadLocal<String> ZITIMC$SERVICE = new ThreadLocal<>();

    @Inject(
        method = "connect(Ljava/net/InetSocketAddress;ZLnet/minecraft/network/Connection;)Lio/netty/channel/ChannelFuture;",
        at = @At("HEAD")
    )
    private static void zitimc$captureZitiAddress(
            InetSocketAddress address,
            boolean useEpoll,
            Connection connection,
            CallbackInfoReturnable<ChannelFuture> cir) {
        if (address instanceof ZitiSocketAddress zsa) {
            ZITIMC$SERVICE.set(zsa.getServiceName());
            ZitiMc.LOG.info("Dialing Ziti service {}", zsa.getServiceName());
        } else {
            ZITIMC$SERVICE.remove();
        }
    }

    @SuppressWarnings({"rawtypes", "unchecked"})
    @Redirect(
        method = "connect(Ljava/net/InetSocketAddress;ZLnet/minecraft/network/Connection;)Lio/netty/channel/ChannelFuture;",
        at = @At(
            value = "INVOKE",
            target = "Lio/netty/bootstrap/Bootstrap;channel(Ljava/lang/Class;)Lio/netty/bootstrap/AbstractBootstrap;",
            remap = false
        )
    )
    private static AbstractBootstrap zitimc$swapChannelFactory(
            Bootstrap bootstrap,
            Class channelClass) {
        String service = ZITIMC$SERVICE.get();
        if (service == null) {
            return bootstrap.channel(channelClass);
        }
        return bootstrap.channelFactory(new ZitiChannelFactory(ZitiMc.zitiContext()));
    }

    @Redirect(
        method = "connect(Ljava/net/InetSocketAddress;ZLnet/minecraft/network/Connection;)Lio/netty/channel/ChannelFuture;",
        at = @At(
            value = "INVOKE",
            target = "Lio/netty/bootstrap/Bootstrap;connect(Ljava/net/InetAddress;I)Lio/netty/channel/ChannelFuture;",
            remap = false
        )
    )
    private static ChannelFuture zitimc$swapConnect(
            Bootstrap bootstrap,
            InetAddress address,
            int port) {
        String service = ZITIMC$SERVICE.get();
        try {
            if (service == null) {
                return bootstrap.connect(address, port);
            }
            zitimc$waitForServiceCatalog(service);
            return bootstrap.connect(new ZitiAddress.Dial(service));
        } finally {
            ZITIMC$SERVICE.remove();
        }
    }

    /**
     * Blocks until the requested service appears in the SDK's catalog or a deadline
     * expires. Uses the SDK's own blocking {@code getService(name, timeoutMillis)} so
     * we wait on actual catalog state rather than wall-clock polling.
     *
     * <p>No retry loop on the dial itself. MC's {@code Connection} handler is
     * {@code @Sharable(false)}, so retrying the {@code Bootstrap.connect} fails on the
     * second attempt with a pipeline exception regardless of the underlying SDK state.
     * Far better to make the first attempt succeed by ensuring the catalog is ready.
     */
    @Unique
    private static void zitimc$waitForServiceCatalog(String service) {
        try {
            Object detail = ZitiMc.zitiContext().getService(service, 30_000L);
            if (detail == null) {
                ZitiMc.LOG.warn("Ziti service '{}' did not appear in the catalog within 30s; dialing anyway", service);
            }
        } catch (Throwable t) {
            ZitiMc.LOG.warn("Ziti service '{}' lookup failed; dialing anyway: {}", service, t.getMessage());
        }
    }
}
