# Hooking Minecraft's Netty stack: building a Fabric mod that routes MC over OpenZiti

A walkthrough of `ziti-minecraft` -- a Fabric mod that swaps Minecraft's TCP socket for an
[OpenZiti](https://openziti.io) overlay channel. No port-forwarding, no public DNS, no
relay. Friends join your world by service name; access is identity-based, enforced by the
overlay before a packet ever reaches your JVM.

This post is for Minecraft mod developers. We assume you know what Fabric, Mixin, and
Netty are. We do not assume you know OpenZiti. Code is real and lives in the repo.

## Why a network mod at all

Three options exist if you want friends to play on your world without exposing a public
listener:

1. **LAN broadcast.** Works on the same Wi-Fi. Useless elsewhere.
2. **Tunnel through a relay.** What e4mc does, what ngrok does. Excellent UX. You pay
   for someone's relay (latency, bandwidth, trust).
3. **Overlay network.** Each peer joins an identity-authenticated overlay; traffic moves
   peer-to-peer or through your own routers, not someone else's product. ZeroTier,
   Tailscale, and OpenZiti all sit here.

OpenZiti is the third option, with two extras that mattered for this build:

- **Service-name addressing.** You dial `my-world` instead of `10.42.0.7:25565`. No IPs,
  no SRV records, no DNS at all.
- **A JVM SDK with a Netty integration**, `ziti-sdk-jvm`. That last detail collapsed the
  entire design space. Read on.

## The architectural insight

Minecraft (Java Edition) is Netty 4.x end to end. Both `net.minecraft.network.Connection`
on the client and `net.minecraft.server.network.ServerConnectionListener` on the server
build standard Netty `Bootstrap` / `ServerBootstrap` chains and call `.channel(...)` and
`.connect(...)` / `.bind(...)`.

`ziti-sdk-jvm` ships a module called `ziti-netty` with these classes:

```
org.openziti.netty.ZitiChannel              extends io.netty.channel.AbstractChannel
org.openziti.netty.ZitiServerChannel        implements ServerChannel
org.openziti.netty.ZitiChannelFactory       implements ChannelFactory<Channel>
org.openziti.netty.ZitiServerChannelFactory
org.openziti.netty.ZitiResolverGroup        for Netty's resolver pipeline
```

These are drop-in Netty channels that speak Ziti. The integration point is exactly one
Bootstrap call away from what Minecraft already does:

```java
new Bootstrap()
    .group(eventLoopGroup)
    .channelFactory(new ZitiChannelFactory(zitiCtx))   // <-- our injection
    .handler(...)
    .connect(new ZitiAddress.Dial("my-service"));      // <-- our other injection
```

So the mod is not a tunnel. It is not a relay. It is not a protocol layer. It is three
Mixin classes that swap two Netty calls.

## Project shape

We used Architectury with Mojmap on Minecraft 1.20.1. The repo layout:

```
ziti-minecraft/
  common/      -- loader-agnostic code: Ziti integration, identity, address parsing,
                  config, Mixin classes targeting Mojmap-named MC classes.
  fabric/      -- ModInitializer + ClientModInitializer + fabric.mod.json.
```

Architectury overkill for a Fabric-only mod? Not quite. NeoForge is the planned second
loader once we bump the MC target, and the cost of keeping the multiloader scaffolding
is negligible compared to the cost of refactoring later.

OpenZiti is bundled via Gradle Shadow's `shadowBundle` into the Fabric jar. Users get
one ~28 MB jar and nothing else to install.

## The 1.20.1 NeoForge detour

Worth a sidebar because it cost real time. NeoForge has two completely different lines:

- **NeoForge 47.x** is the MC 1.20.1 line. It is essentially a Forge fork that kept the
  legacy userdev structure.
- **NeoForge 20.4+** is MC 1.20.2 onward. New userdev format, modern Gradle integration,
  Loom's `neoForge()` configuration was written for this line.

If you target MC 1.20.1 and try to use Architectury Loom's `neoForge()` setup, you get:

```
Could not find method neoForge() for arguments [net.neoforged:neoforge:47.1.106]
```

Switching to `forge()` swaps the error for a similar one with the `forge` configuration.
The right answer for 1.20.1 multiloader is either:

- Use Loom's legacy Forge plugin with `net.minecraftforge:forge:1.20.1-47.X.X` and live
  without the NeoForge brand on this version, or
- Bump the MC target to 1.20.4+ so Loom's modern `neoForge()` config works.

We dropped NeoForge from v1 on 1.20.1. NeoForge's install base on 1.20.1 is small; Fabric
covers the 1.20.1 modder audience cleanly. The Architectury scaffolding stays so adding
NeoForge later is a new module, not a rewrite.

Other version-pin lessons:

- Architectury API 9.2.14 needs Architectury Loom 1.5+. We pinned 1.6-SNAPSHOT.
- Gradle 8.6 is the sweet spot for Loom 1.6 + the version of Shadow we use.

## The Mixin design

Three Mixin classes, all in `common/`:

1. `ServerNameResolverMixin` (client only) -- short-circuits DNS for Ziti service names.
2. `ConnectionMixin` (client only) -- swaps the Netty channel factory and connect address.
3. `ServerConnectionListenerMixin` (server) -- planned for the bind side. Stub for now.

The pattern we used to ferry a service name from "user typed it in the address field" to
"Ziti SDK dials it" is the **smuggler InetSocketAddress** pattern, borrowed from
[e4mc](https://github.com/vgskye/e4mc-minecraft-architectury).

### The smuggler

A subclass of `InetSocketAddress` that carries one extra field:

```java
public final class ZitiSocketAddress extends InetSocketAddress {
    private final String serviceName;

    public ZitiSocketAddress(String serviceName) {
        super(0);  // wildcard, port 0 -- never actually used for TCP
        this.serviceName = serviceName;
    }

    public String getServiceName() {
        return serviceName;
    }
}
```

Why this is the right shape: every method in Minecraft's resolution and connection
pipeline takes or returns `InetSocketAddress` (or types that wrap one). A subclass flows
through every signature without us needing access transformers or extra Mixins. The
service-name field is `private` and accessed only at the Connection mixin's point of use.

The `super(0)` call avoids DNS resolution. `InetSocketAddress(String, int)` would block
trying to resolve the host. `InetSocketAddress(int)` uses the wildcard address. We never
actually use the inherited host/port -- the moment Connection sees a `ZitiSocketAddress`,
we hijack and never touch the inherited fields.

### Mixin 1: ServerNameResolverMixin

Minecraft's resolution path for "join server":

```
ServerAddress.parseString("my-world")        // text from the Add Server screen
  -> ServerAddress { host="my-world", port=25565 }
ServerNameResolver.resolveAddress(addr)       // returns Optional<ResolvedServerAddress>
  -> JNDI SRV lookup, then DNS, then a synthetic Resolved if both fail
Connection.connect(resolved.asInetSocketAddress(), ...)
```

We want to short-circuit `resolveAddress` for Ziti service names. The whole Mixin:

```java
@Mixin(ServerNameResolver.class)
public abstract class ServerNameResolverMixin {
    @Inject(method = "resolveAddress", at = @At("HEAD"), cancellable = true)
    private void zitimc$resolveAsZitiService(
            ServerAddress address,
            CallbackInfoReturnable<Optional<ResolvedServerAddress>> cir) {
        String host = address.getHost();
        if (!ZitiServiceAddress.isZitiServiceName(host)) return;
        String service = ZitiServiceAddress.normalize(host);
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
```

`ZitiServiceAddress.isZitiServiceName` is the rule that decides what counts as a Ziti
service. v1 default: no dot, no colon, not all-digits. Configurable to a stricter
`ziti:`-prefix mode for users who want to be explicit.

One mistake worth flagging: I first wrote this as `interface` (with `default` method),
which is fine for many Mixin patterns but fails when the target class is itself a
concrete class. The Mixin compiler is loud about this:

```
Targetted type 'net.minecraft.client.multiplayer.resolver.ServerNameResolver' is not an interface
```

Fix: `abstract class` with `private` method.

### Mixin 2: ConnectionMixin

This is where the actual channel swap happens. The Minecraft method we target on 1.20.1
Mojmap is:

```java
public static ChannelFuture connect(InetSocketAddress address, boolean useEpoll, Connection connection)
```

Inside it, MC builds a `Bootstrap` and calls `.channel(NioSocketChannel.class)` then
`.connect(address.getAddress(), address.getPort())`. We need to swap both.

We use a `ThreadLocal<String>` to ferry the service name from a HEAD inject to the two
`@Redirect`s. ThreadLocal is safe here because each connect runs on its own dedicated
"Server Connector" thread that MC spawns per dial:

```java
@Mixin(Connection.class)
public abstract class ConnectionMixin {

    @Unique
    private static final ThreadLocal<String> ZITIMC$SERVICE = new ThreadLocal<>();

    @Inject(
        method = "connect(Ljava/net/InetSocketAddress;ZLnet/minecraft/network/Connection;)Lio/netty/channel/ChannelFuture;",
        at = @At("HEAD")
    )
    private static void zitimc$captureZitiAddress(
            InetSocketAddress address, boolean useEpoll, Connection connection,
            CallbackInfoReturnable<ChannelFuture> cir) {
        if (address instanceof ZitiSocketAddress zsa) {
            ZITIMC$SERVICE.set(zsa.getServiceName());
        } else {
            ZITIMC$SERVICE.remove();
        }
    }

    @SuppressWarnings({"rawtypes", "unchecked"})
    @Redirect(
        method = "connect(Ljava/net/InetSocketAddress;ZLnet/minecraft/network/Connection;)Lio/netty/channel/ChannelFuture;",
        at = @At(value = "INVOKE", target = "Lio/netty/bootstrap/AbstractBootstrap;channel(Ljava/lang/Class;)Lio/netty/bootstrap/AbstractBootstrap;")
    )
    private static AbstractBootstrap zitimc$swapChannelFactory(
            AbstractBootstrap bootstrap, Class channelClass) {
        String service = ZITIMC$SERVICE.get();
        if (service == null) return bootstrap.channel(channelClass);
        return ((Bootstrap) bootstrap).channelFactory(
            new ZitiChannelFactory(ZitiMc.zitiContext()));
    }

    @Redirect(
        method = "connect(Ljava/net/InetSocketAddress;ZLnet/minecraft/network/Connection;)Lio/netty/channel/ChannelFuture;",
        at = @At(value = "INVOKE", target = "Lio/netty/bootstrap/Bootstrap;connect(Ljava/net/InetAddress;I)Lio/netty/channel/ChannelFuture;")
    )
    private static ChannelFuture zitimc$swapConnect(
            Bootstrap bootstrap, InetAddress address, int port) {
        String service = ZITIMC$SERVICE.get();
        try {
            if (service == null) return bootstrap.connect(address, port);
            return bootstrap.connect(new ZitiAddress.Dial(service));
        } finally {
            ZITIMC$SERVICE.remove();
        }
    }
}
```

Three gotchas worth calling out:

1. **Raw types on `AbstractBootstrap`.** `AbstractBootstrap<?, ?>` loses the type
   parameter that `channel(Class<? extends C>)` needs. Going raw + `@SuppressWarnings` is
   the least-bad option for Mixin handler code. You will not be sorry.

2. **The Mixin annotation processor cannot validate Netty `@At` targets without help.**
   It warns:

   ```
   Unable to locate method mapping for @At(INVOKE.<target>) 'Lio/netty/bootstrap/Bootstrap;channel(...)...'
   ```

   Netty is not part of Minecraft's mapping data so the AP cannot remap or validate.
   The fix is one annotation flag: `remap = false` on the `@At` block. That tells the
   AP "the descriptor is already in runtime form, don't touch it." Warnings vanish.

3. **The owner of the bytecode `INVOKE` ref matters.** MC source code reads
   `bootstrap.channel(NioSocketChannel.class)`, but the `bootstrap` variable is typed
   `Bootstrap`, so javac emits `INVOKEVIRTUAL Bootstrap.channel(Class)AbstractBootstrap`
   even though `channel` is inherited from `AbstractBootstrap`. Our first attempt
   targeted `AbstractBootstrap` as the owner and Mixin said `Scanned 0 target(s)` at
   runtime, crashing the entire class transform. The owner string in `@At target`
   has to exactly match the static call-site type, not the declaring class.
   `javap -c` against the Mojmap-remapped MC jar (Loom puts it under
   `.gradle/loom-cache/`) is the fastest way to see what owner javac actually emitted.

4. **The connect call descriptor matters.** MC 1.20.1 calls
   `bootstrap.connect(address.getAddress(), address.getPort())` -- two args, an
   `InetAddress` and an `int`. The descriptor is
   `(Ljava/net/InetAddress;I)Lio/netty/channel/ChannelFuture;`. If a future MC version
   refactors to `bootstrap.connect(SocketAddress)`, the Redirect silently no-ops. Pin
   the version range in `fabric.mod.json`.

### Mixin 3: ServerConnectionListenerMixin

The server-side counterpart. Modeled after e4mc's same-named class. Pattern:

```java
@Mixin(ServerConnectionListener.class)
public abstract class ServerConnectionListenerMixin {

    @Shadow @Final private List<ChannelFuture> channels;

    @Unique private ChannelHandler zitimc$childHandler;
    @Unique private EventLoopGroup zitimc$group;

    @ModifyArg(
        method = "startTcpServerListener",
        at = @At(value = "INVOKE",
            target = "Lio/netty/bootstrap/ServerBootstrap;childHandler(Lio/netty/channel/ChannelHandler;)Lio/netty/bootstrap/ServerBootstrap;",
            remap = false))
    private ChannelHandler zitimc$captureChildHandler(ChannelHandler h) {
        this.zitimc$childHandler = h;
        return h;
    }

    // ...same shape for group(EventLoopGroup)...

    @Inject(method = "startTcpServerListener", at = @At("TAIL"))
    private void zitimc$bindZitiListener(InetAddress address, int port, CallbackInfo ci) {
        if (!ZitiMc.config().serverBind.enabled) return;
        String service = ZitiMc.config().serverBind.serviceName;

        ServerBootstrap bootstrap = new ServerBootstrap();
        bootstrap.channelFactory(new ZitiServerChannelFactory(ZitiMc.zitiContext()));
        bootstrap.childHandler(this.zitimc$childHandler);
        bootstrap.group(this.zitimc$group);
        ChannelFuture future = bootstrap.bind(new ZitiAddress.Bind(service))
            .syncUninterruptibly();
        this.channels.add(future);
    }
}
```

The neat detail is the `@Shadow @Final` on vanilla's `channels` list. By appending the
Ziti `ChannelFuture` to that list, vanilla's existing `stop()` loop closes it for us --
no separate `@Inject(at = HEAD)` on `stop()` needed.

Gated by `config.serverBind.enabled`. Defaults off so installations that only need the
client side do not spin up a Ziti listener.

## Identity wiring

OpenZiti expects an identity to dial. The JVM SDK loads one with:

```java
ZitiContext ctx = Ziti.newContext(new File("identity.json"), new char[0]);
```

That file is the output of enrolling a one-time JWT against a Ziti controller. v1 of
this mod does NOT do in-process enrollment -- it tells the user to run
`ziti edge enroll --jwt enrollment.jwt` to produce the JSON, then point the mod at it.
In-process enrollment needs PKCS12 keystore management and is not worth the surface area
until a real user asks.

We wrapped the load in a pluggable interface up front because zrok integration is a
planned follow-up. The interface:

```java
public interface IdentityProvider {
    ZitiContext load() throws IOException;
    String describe();
}
```

`FileIdentityProvider` is v1. `ZrokIdentityProvider` is v1.x. Same interface; the Mixin
code never has to change.

`ZitiContext` itself is held in `ZitiMc` and lazy-loaded on first call. The first
implementation just did the load and returned. That broke immediately under MC's
"Server List Pinger" thread, which fires a connect for every entry in your server list
the moment you open the multiplayer screen -- *before* the Ziti SDK has finished its
async controller authentication and service-catalog fetch. Dials raced and got
`ServiceNotAvailable`.

Fix: block in `zitiContext()` until the SDK reports `Status.Active` (or hits a terminal
state, or a deadline):

```java
public static ZitiContext zitiContext() {
    ZitiContext ctx = ZITI_CONTEXT;
    if (ctx != null) return ctx;
    synchronized (ZitiMc.class) {
        if (ZITI_CONTEXT != null) return ZITI_CONTEXT;
        try {
            ZitiContext loaded = IDENTITY.load();
            waitForActive(loaded);   // <-- new
            ZITI_CONTEXT = loaded;
        } catch (IOException ioe) {
            throw new RuntimeException("Ziti identity not available: " + ioe.getMessage(), ioe);
        }
        return ZITI_CONTEXT;
    }
}

private static void waitForActive(ZitiContext ctx) {
    long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(15);
    while (System.nanoTime() < deadline) {
        ZitiContext.Status status = ctx.getStatus();
        if (status instanceof ZitiContext.Status.Active) return;
        if (status instanceof ZitiContext.Status.NotAuthorized
                || status instanceof ZitiContext.Status.Unavailable
                || status instanceof ZitiContext.Status.Disabled) {
            throw new RuntimeException("Ziti context terminal state: " + status);
        }
        try { Thread.sleep(100); } catch (InterruptedException ie) {
            Thread.currentThread().interrupt(); return;
        }
    }
    LOG.warn("Ziti context did not reach Active within 15s; dials may fail");
}
```

The first dial pays one warm-up tax of a second or two. Subsequent dials hit the
double-checked locking fast path. Lazy because: a player who never types a Ziti service
name should never see an identity-load error. If you launch MC with no identity
configured and only ever connect to vanilla TCP servers, the mod is silent.

## Configuration

`config/openziti.json` (auto-created with defaults on first run):

```json
{
  "identityPath": "config/openziti/identity.json",
  "addressDetection": "implicit",
  "serverBind": { "enabled": false, "serviceName": "" }
}
```

`addressDetection` toggles between the "no dot, no colon" heuristic and a strict
`ziti:`-prefix mode. The heuristic is friendly; the prefix is unambiguous. Some users
will want one, some the other.

## What we explicitly chose NOT to do

Lessons cost time too:

- **No custom URI scheme.** `ziti://my-service` would require a separate Mixin on the
  `ServerAddress` parser. The free text field works.
- **No new in-game screen.** Multiplayer / Add Server already exists.
- **No replacement of MC's protocol.** Only the transport. The whole point of the
  Netty channel factory hook is that Minecraft's packet pipeline does not know it is
  riding on Ziti.
- **No tunnel daemon.** Some related projects ship a sidecar process; we let the SDK
  live in-JVM. One process, one jar.

## State

Both directions wired and validated against a real Ziti controller:

- Client side: type `my-service` into Add Server, mod resolves and dials via Ziti.
- Server side: dedicated/integrated server binds on a Ziti service alongside its
  normal TCP listener (gated by `config.serverBind.enabled`).
- An MC server connection over Ziti reaches the protocol layer; on first end-to-end
  test the server logged the inbound `GameProfile` with the dialing Ziti identity
  visible in `Connection.toString()` -- the SDK passes `callerId=<dialing-identity>`
  through to `ServerBootstrap`'s accept handler. Beautiful detail you do not have to
  build yourself.

One gotcha to know about when testing in dev: vanilla `server.properties` defaults to
`online-mode=true`, so the server tries to Mojang-authenticate the dev client's
offline `Player###` profile and rejects it with `lost connection: Disconnected`. Set
`online-mode=false` in `run-server/server.properties` for dev. Production deployments
keep online-mode on; that is unrelated to anything Ziti is doing.

One warning we did not chase: the `architectury-plugin` prints `You are using an
outdated version of Architectury Loom!` on every configure phase. We pinned Loom 1.6,
which is the last line that cleanly supports MC 1.20.1. Newer Loom (1.10+ era) targets
1.21+. The warning is cosmetic and will go away if/when we bump the MC target.

Repo: https://github.com/dovholuknf/ziti-minecraft (Apache-2.0).

## Credits and references

- [vgskye/e4mc-minecraft-architectury](https://github.com/vgskye/e4mc-minecraft-architectury)
  for the smuggler-InetSocketAddress pattern and the Connection / ServerConnectionListener
  Mixin shapes. We did not copy code, but we copied the design.
- [openziti/ziti-sdk-jvm](https://github.com/openziti/ziti-sdk-jvm) for the SDK. The
  `ziti-netty` module is what made this a 200-line mod instead of a 2000-line mod.
- [OpenZiti documentation](https://openziti.io) for the protocol and concepts.

If you build something with this pattern -- routing MC over your own overlay,
zerotrust-ifying a dedicated server, anything in that space -- I would like to read the
post.
