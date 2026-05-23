package org.openziti.minecraft.mixin;

import io.netty.bootstrap.ServerBootstrap;
import io.netty.channel.ChannelFuture;
import io.netty.channel.ChannelHandler;
import io.netty.channel.EventLoopGroup;
import net.minecraft.server.network.ServerConnectionListener;
import org.openziti.ZitiAddress;
import org.openziti.minecraft.ZitiMc;
import org.openziti.netty.ZitiServerChannelFactory;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Shadow;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.ModifyArg;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

import java.net.InetAddress;
import java.util.List;

/**
 * Hooks the dedicated/integrated server's TCP listener so we additionally bind on
 * a Ziti service when {@code serverBind.enabled} is true in the config.
 *
 * <p>Modeled after e4mc's ServerConnectionListenerMixin: capture the
 * {@link EventLoopGroup} and child {@link ChannelHandler} that vanilla passes to its
 * {@link ServerBootstrap}, then at the TAIL of {@code startTcpServerListener} stand up
 * a second {@link ServerBootstrap} that uses {@link ZitiServerChannelFactory} and binds
 * to a {@link ZitiAddress.Bind}. The resulting {@link ChannelFuture} is added to
 * vanilla's own {@code channels} list so {@link ServerConnectionListener#stop()} closes
 * it for us.
 */
@Mixin(ServerConnectionListener.class)
public abstract class ServerConnectionListenerMixin {

    @Shadow
    @org.spongepowered.asm.mixin.Final
    private List<ChannelFuture> channels;

    @Unique
    private ChannelHandler zitimc$childHandler;

    @Unique
    private EventLoopGroup zitimc$group;

    @ModifyArg(
        method = "startTcpServerListener",
        at = @At(
            value = "INVOKE",
            target = "Lio/netty/bootstrap/ServerBootstrap;childHandler(Lio/netty/channel/ChannelHandler;)Lio/netty/bootstrap/ServerBootstrap;",
            remap = false
        )
    )
    private ChannelHandler zitimc$captureChildHandler(ChannelHandler childHandler) {
        this.zitimc$childHandler = childHandler;
        return childHandler;
    }

    @ModifyArg(
        method = "startTcpServerListener",
        at = @At(
            value = "INVOKE",
            target = "Lio/netty/bootstrap/ServerBootstrap;group(Lio/netty/channel/EventLoopGroup;)Lio/netty/bootstrap/ServerBootstrap;",
            remap = false
        )
    )
    private EventLoopGroup zitimc$captureGroup(EventLoopGroup group) {
        this.zitimc$group = group;
        return group;
    }

    @SuppressWarnings({"rawtypes", "unchecked"})
    @Inject(method = "startTcpServerListener", at = @At("TAIL"))
    private void zitimc$bindZitiListener(InetAddress address, int port, CallbackInfo ci) {
        try {
            if (!ZitiMc.config().serverBind.enabled) {
                return;
            }
            String service = ZitiMc.config().serverBind.serviceName;
            if (service == null || service.isEmpty()) {
                ZitiMc.LOG.warn("serverBind.enabled=true but serverBind.serviceName is empty; not binding Ziti listener");
                return;
            }
            ChannelHandler childHandler = this.zitimc$childHandler;
            EventLoopGroup group = this.zitimc$group;
            if (childHandler == null || group == null) {
                ZitiMc.LOG.error("Failed to capture child handler or event group; cannot bind Ziti listener");
                return;
            }

            ZitiMc.LOG.info("Binding Minecraft server to Ziti service '{}'", service);
            ServerBootstrap bootstrap = new ServerBootstrap();
            bootstrap.channelFactory(new ZitiServerChannelFactory(ZitiMc.zitiContext()));
            bootstrap.childHandler(childHandler);
            bootstrap.group(group);
            ChannelFuture zitiFuture = bootstrap.bind(new ZitiAddress.Bind(service)).syncUninterruptibly();
            this.channels.add(zitiFuture);
            ZitiMc.LOG.info("Ziti listener bound on service '{}'", service);

            if (ZitiMc.config().serverBind.disableTcp) {
                ZitiMc.LOG.info("Closing vanilla TCP listener(s) (serverBind.disableTcp=true)");
                for (int i = this.channels.size() - 1; i >= 0; i--) {
                    ChannelFuture cf = this.channels.get(i);
                    if (cf == zitiFuture) continue;
                    try {
                        cf.channel().close().syncUninterruptibly();
                        this.channels.remove(i);
                    } catch (Throwable t) {
                        ZitiMc.LOG.warn("Failed to close TCP listener channel", t);
                    }
                }
            }
        } catch (Throwable t) {
            ZitiMc.LOG.error("Failed to bind Ziti listener", t);
        } finally {
            // Don't keep references around after server start.
            this.zitimc$childHandler = null;
            this.zitimc$group = null;
        }
    }
}
