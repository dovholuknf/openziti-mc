package org.openziti.minecraft.fabric;

import com.terraformersmc.modmenu.api.ConfigScreenFactory;
import com.terraformersmc.modmenu.api.ModMenuApi;
import me.shedaniel.autoconfig.AutoConfig;
import me.shedaniel.clothconfig2.api.ConfigBuilder;
import me.shedaniel.clothconfig2.api.ConfigCategory;
import me.shedaniel.clothconfig2.api.ConfigEntryBuilder;
import net.minecraft.network.chat.Component;
import org.openziti.ZitiContext;
import org.openziti.minecraft.ZitiMc;
import org.openziti.minecraft.config.ZitiMcConfig;

import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

/**
 * Cloth Config screen for OpenZiti MC. Built imperatively (ConfigBuilder) instead of
 * letting AutoConfig auto-generate it, so we can show diagnostic status at the top of
 * the screen (identity file presence, Ziti context state).
 */
public final class ZitiMcModMenu implements ModMenuApi {

    @Override
    public ConfigScreenFactory<?> getModConfigScreenFactory() {
        return parent -> {
            ZitiMcConfig cfg = ZitiMc.config();

            ConfigBuilder builder = ConfigBuilder.create()
                .setParentScreen(parent)
                .setTitle(Component.translatable("text.autoconfig.openziti.title"))
                .setSavingRunnable(() -> {
                    try {
                        AutoConfig.getConfigHolder(ZitiMcConfig.class).save();
                    } catch (Throwable t) {
                        ZitiMc.LOG.error("Failed to save OpenZiti MC config from settings screen", t);
                    }
                });

            ConfigEntryBuilder eb = builder.entryBuilder();
            ConfigCategory cat = builder.getOrCreateCategory(Component.literal("OpenZiti"));

            // -- Status block ----------------------------------------------------

            cat.addEntry(eb.startTextDescription(identityStatusComponent(cfg.identityPath)).build());
            cat.addEntry(eb.startTextDescription(zitiContextStatusComponent()).build());

            // -- Editable settings -----------------------------------------------
            // identityPath is intentionally not exposed in the UI -- the status block
            // above shows whether it was found, and the default path
            // (config/openziti/identity.json) works for everyone. Power users can
            // still override via direct edit of config/openziti.json.

            cat.addEntry(eb.startTextDescription(
                Component.literal("§7Open to OpenZiti (not necessary if you run a separate dedicated server with OpenZiti)")).build());

            cat.addEntry(eb.startBooleanToggle(
                    Component.translatable("text.autoconfig.openziti.option.serverEnabled"),
                    cfg.serverEnabled)
                .setDefaultValue(false)
                .setTooltip(Component.translatable("text.autoconfig.openziti.option.serverEnabled.@Tooltip"))
                .setSaveConsumer(v -> cfg.serverEnabled = v)
                .requireRestart()
                .build());

            cat.addEntry(eb.startStrField(
                    Component.translatable("text.autoconfig.openziti.option.serviceName"),
                    cfg.serviceName)
                .setDefaultValue("openziti-mc")
                .setTooltip(Component.translatable("text.autoconfig.openziti.option.serviceName.@Tooltip"))
                .setSaveConsumer(v -> cfg.serviceName = v)
                .requireRestart()
                .build());

            return builder.build();
        };
    }

    private static Component identityStatusComponent(String identityPath) {
        Path p = Paths.get(identityPath).toAbsolutePath();
        if (Files.isRegularFile(p)) {
            long sizeKb = 0;
            try {
                sizeKb = Math.round(Files.size(p) / 1024.0);
            } catch (Throwable ignored) {
                // best-effort size reporting; the find is what matters
            }
            return Component.literal("§aIdentity file: FOUND ").append(
                Component.literal("(" + sizeKb + " KB at " + p + ")").withStyle(style -> style.withColor(0xAAAAAA)));
        }
        return Component.literal("§cIdentity file: NOT FOUND").append(
            Component.literal(" (expected at " + p + ")").withStyle(style -> style.withColor(0xAAAAAA)));
    }

    private static Component zitiContextStatusComponent() {
        ZitiContext ctx = ZitiMc.zitiContextOrNull();
        if (ctx == null) {
            return Component.literal("§eZiti context: not loaded yet (warm-up may still be in progress, or no identity)");
        }
        ZitiContext.Status status = ctx.getStatus();
        String label;
        String color;
        if (status instanceof ZitiContext.Status.Active) {
            label = "Active";
            color = "§a";
        } else if (status instanceof ZitiContext.Status.Loading) {
            label = "Loading";
            color = "§e";
        } else if (status instanceof ZitiContext.Status.NeedsAuth) {
            label = "Needs auth";
            color = "§e";
        } else if (status instanceof ZitiContext.Status.NotAuthorized) {
            label = "Not authorized";
            color = "§c";
        } else if (status instanceof ZitiContext.Status.Unavailable) {
            label = "Unavailable";
            color = "§c";
        } else if (status instanceof ZitiContext.Status.Disabled) {
            label = "Disabled";
            color = "§c";
        } else {
            label = status.getClass().getSimpleName();
            color = "§7";
        }
        return Component.literal(color + "Ziti context: " + label);
    }
}
