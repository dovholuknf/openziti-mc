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
            return zitimc$dialWithRetry(bootstrap, service);
        } finally {
            ZITIMC$SERVICE.remove();
        }
    }

    /**
     * The Ziti router can fail to route the first dial right after a service catalog
     * sync ("exceeded maximum [2] retries creating circuit ... failed to establish
     * connection with terminator"), even though the terminator is registered and
     * healthy. A short retry catches this gracefully so the user does not have to click
     * Join Server twice.
     */
    @Unique
    private static ChannelFuture zitimc$dialWithRetry(Bootstrap bootstrap, String service) {
        int maxAttempts = 5;
        long perAttemptTimeoutMs = 3000L;
        long backoffMs = 500L;
        ChannelFuture last = null;
        for (int attempt = 1; attempt <= maxAttempts; attempt++) {
            ChannelFuture future = bootstrap.connect(new ZitiAddress.Dial(service));
            boolean completed;
            try {
                completed = future.await(perAttemptTimeoutMs, TimeUnit.MILLISECONDS);
            } catch (InterruptedException ie) {
                Thread.currentThread().interrupt();
                return future;
            }
            if (completed && future.isSuccess()) {
                if (attempt > 1) {
                    ZitiMc.LOG.info("Ziti dial '{}' succeeded on attempt {}", service, attempt);
                }
                return future;
            }
            last = future;
            Throwable cause = future.cause();
            ZitiMc.LOG.warn("Ziti dial '{}' attempt {}/{} failed: {}",
                service, attempt, maxAttempts,
                cause != null ? cause.getMessage() : "timeout");
            try {
                if (future.channel() != null) future.channel().close();
            } catch (Throwable ignored) {
                // Best-effort cleanup; if the channel can't close, the GC will handle it.
            }
            try {
                Thread.sleep(backoffMs);
            } catch (InterruptedException ie) {
                Thread.currentThread().interrupt();
                return future;
            }
        }
        return last;
    }

    /**
     * The Ziti SDK reports {@code Status.Active} as soon as the controller authenticates,
     * but the initial service catalog sync arrives milliseconds later. The first dial
     * after a fresh load therefore races and gets {@code ServiceNotAvailable}. Poll the
     * context's catalog until the target service appears (or the deadline expires) so the
     * first dial succeeds.
     */
    @Unique
    private static void zitimc$waitForServiceCatalog(String service) {
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5);
        while (System.nanoTime() < deadline) {
            try {
                if (ZitiMc.zitiContext().getService(service) != null) {
                    return;
                }
            } catch (Throwable ignored) {
                // SDK can throw if catalog is mid-sync; retry until deadline.
            }
            try {
                Thread.sleep(100);
            } catch (InterruptedException ie) {
                Thread.currentThread().interrupt();
                return;
            }
        }
        ZitiMc.LOG.warn("Ziti service '{}' not in catalog after 5s; dialing anyway", service);
    }
}
