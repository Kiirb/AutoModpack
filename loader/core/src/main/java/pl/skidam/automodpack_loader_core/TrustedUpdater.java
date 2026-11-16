package pl.skidam.automodpack_loader_core;

import com.google.gson.Gson;
import pl.skidam.automodpack_core.utils.HttpClientPool;
import pl.skidam.automodpack_core.utils.SemanticVersion;
import pl.skidam.automodpack_loader_core.platforms.ModrinthAPI;

import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;

import static pl.skidam.automodpack_core.GlobalVariables.*;

/**
 * [trusted-server patch] Self-updater that only ever installs the patched
 * "trusted-server" AutoModpack build published on our own GitHub fork,
 * never the official jar from Modrinth.
 *
 * Reads {@link #MANIFEST_URL}, picks the entry for the running Minecraft
 * version + loader, and installs it if its version is newer than the running one.
 */
public final class TrustedUpdater {

    public static final String MANIFEST_URL =
            "https://github.com/Kiirb/AutoModpack/releases/latest/download/trusted-manifest.json";

    private TrustedUpdater() {}

    static final class Manifest {
        List<Entry> files;
    }

    static final class Entry {
        String version;
        String mcVersion;
        String loader;
        String fileName;
        String url;
        String sha1;
        long size;
    }

    /** @return true if an update was installed and the game is restarting. */
    public static boolean update() {
        Manifest manifest;
        try {
            HttpResponse<byte[]> response = HttpClientPool.request(MANIFEST_URL,
                    Map.of("User-Agent", "automodpack-trusted/" + AM_VERSION), null, true);
            if (response.statusCode() != 200) {
                LOGGER.warn("[trusted-server patch] Update manifest returned HTTP {}", response.statusCode());
                return false;
            }
            manifest = new Gson().fromJson(new String(response.body(), StandardCharsets.UTF_8), Manifest.class);
        } catch (Exception e) {
            LOGGER.warn("[trusted-server patch] Couldn't fetch update manifest: {}", e.toString());
            return false;
        }

        if (manifest == null || manifest.files == null) {
            LOGGER.warn("[trusted-server patch] Update manifest is empty or invalid");
            return false;
        }

        Entry entry = manifest.files.stream()
                .filter(e -> e != null && MC_VERSION != null && MC_VERSION.equals(e.mcVersion)
                        && LOADER != null && LOADER.equalsIgnoreCase(e.loader))
                .findFirst().orElse(null);

        if (entry == null) {
            LOGGER.info("[trusted-server patch] No patched build published for {} {}", LOADER, MC_VERSION);
            return false;
        }
        if (entry.url == null || !entry.url.startsWith("https://") || entry.sha1 == null
                || entry.fileName == null || entry.version == null || entry.size <= 0) {
            LOGGER.warn("[trusted-server patch] Ignoring incomplete manifest entry for {} {}", LOADER, MC_VERSION);
            return false;
        }

        // Like the official updater: only update to a newer version. The jar keeps the
        // official file name, so installing the same version would overwrite itself.
        try {
            SemanticVersion current = SemanticVersion.parse(AM_VERSION);
            SemanticVersion remote = SemanticVersion.parse(entry.version);
            if (remote.compareTo(current) <= 0) {
                LOGGER.info("[trusted-server patch] AutoModpack is up to date ({}, latest patched build {})",
                        AM_VERSION, entry.version);
                return false;
            }
            if (!SelfUpdater.validUpdate(remote)) return false;
        } catch (IllegalArgumentException e) {
            LOGGER.warn("[trusted-server patch] Invalid version in manifest: {}", entry.version);
            return false;
        }

        LOGGER.info("[trusted-server patch] Installing patched AutoModpack {} ({})", entry.version, entry.fileName);
        SelfUpdater.installModVersion(new ModrinthAPI(null, MANIFEST_URL, entry.url, entry.version,
                entry.fileName, entry.size, "release", entry.sha1.toLowerCase()));
        return true;
    }
}
