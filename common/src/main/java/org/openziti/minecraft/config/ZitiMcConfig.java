package org.openziti.minecraft.config;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import org.openziti.minecraft.ZitiMc;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

public final class ZitiMcConfig {

    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().create();

    public String identityPath = "config/openziti/identity.json";
    public String addressDetection = "implicit"; // "implicit" | "prefix"
    public ServerBind serverBind = new ServerBind();

    public static final class ServerBind {
        public boolean enabled = false;
        public String serviceName = "";
        /** When true and {@link #enabled} is true, the vanilla TCP listener is closed
         *  right after the Ziti listener binds. Zero-trust posture -- nothing on 25565. */
        public boolean disableTcp = false;
    }

    public static ZitiMcConfig loadOrCreate(Path file) {
        try {
            if (!Files.exists(file)) {
                Files.createDirectories(file.getParent());
                ZitiMcConfig defaults = new ZitiMcConfig();
                Files.writeString(file, GSON.toJson(defaults));
                return defaults;
            }
            return GSON.fromJson(Files.readString(file), ZitiMcConfig.class);
        } catch (IOException ioe) {
            ZitiMc.LOG.error("Failed to load {} -- using defaults", file, ioe);
            return new ZitiMcConfig();
        }
    }
}
