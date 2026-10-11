package dev.palcraft.bridge.link;
import java.nio.file.Path;
public final class BridgePaths {
    private BridgePaths() {}
    /** The folder both games share: -Dpalcraft.dir, else PALCRAFT_DIR, else %LOCALAPPDATA%\PalCraft\runtime. */
    public static String file(String name) {
        String dir = System.getProperty("palcraft.dir");
        if (dir == null || dir.isBlank()) dir = System.getenv("PALCRAFT_DIR");
        if (dir == null || dir.isBlank()) {
            String local = System.getenv("LOCALAPPDATA");
            dir = local != null && !local.isBlank() ? Path.of(local, "PalCraft", "runtime").toString()
                : Path.of(System.getProperty("java.io.tmpdir"), "palcraft").toString();
        }
        java.io.File folder = new java.io.File(dir);
        if (!folder.isDirectory()) folder.mkdirs();
        return Path.of(dir, name).toString();
    }
}
