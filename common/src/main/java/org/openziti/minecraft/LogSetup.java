package org.openziti.minecraft;

import org.apache.logging.log4j.Level;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.core.LoggerContext;
import org.apache.logging.log4j.core.appender.FileAppender;
import org.apache.logging.log4j.core.config.Configuration;
import org.apache.logging.log4j.core.config.LoggerConfig;
import org.apache.logging.log4j.core.layout.PatternLayout;

import java.nio.file.Files;
import java.nio.file.Paths;

/**
 * Attaches a Log4j2 file appender so OpenZiti MC's log output also lands in a
 * dedicated file at {@code logs/openziti-mc.log} (in addition to Minecraft's shared
 * {@code logs/latest.log}). Captures the mod's own logger plus the bundled Ziti SDK.
 */
final class LogSetup {
    private LogSetup() {}

    static void attachFileAppender() {
        try {
            var logFile = Paths.get("logs", "openziti-mc.log");
            Files.createDirectories(logFile.getParent());

            var ctx = (LoggerContext) LogManager.getContext(false);
            Configuration config = ctx.getConfiguration();

            PatternLayout layout = PatternLayout.newBuilder()
                .withConfiguration(config)
                .withPattern("[%d{yyyy-MM-dd HH:mm:ss.SSS}] [%thread/%level] [%logger] %msg%n%xEx")
                .build();

            FileAppender appender = FileAppender.newBuilder()
                .setName("OpenZitiMcFile")
                .withFileName(logFile.toString())
                .setLayout(layout)
                .setConfiguration(config)
                .build();
            appender.start();
            config.addAppender(appender);

            // additive=true so lines still bubble up to MC's root appenders -- the mod
            // log file is additional, not a replacement for latest.log.
            for (String loggerName : new String[]{"ziti-minecraft", "org.openziti"}) {
                LoggerConfig lc = new LoggerConfig(loggerName, Level.INFO, true);
                lc.addAppender(appender, null, null);
                config.addLogger(loggerName, lc);
            }
            ctx.updateLoggers();
        } catch (Throwable t) {
            // Never crash the mod just because we couldn't open a log file.
            ZitiMc.LOG.error("Failed to attach openziti-mc.log file appender", t);
        }
    }
}
