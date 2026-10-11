package dev.palcraft.bridge;

import dev.palcraft.bridge.gen.Tune;
import dev.palcraft.bridge.link.ErLink;
import net.minecraft.server.MinecraftServer;

/**
 * System "autosave": Minecraft only writes a single-player world when the player quits through its menu, and
 * here nobody does. The launcher stops both games from outside, so the world is saved on a short timer and
 * the moment Palworld's side of the link goes quiet.
 */
public final class Autosave {
	private Autosave() {
	}

	private static long nextAt;
	private static boolean wasAlive;

	public static void onServerTick(MinecraftServer server) {
		if (!TerrainManager.isBridgeWorld()) {
			return;
		}
		boolean alive = ErLink.get().alive();
		long now = System.currentTimeMillis();
		boolean lost = wasAlive && !alive;
		wasAlive = alive;
		if (nextAt == 0L) {
			nextAt = now + (long) (Tune.AUTOSAVE_S * 1000.0);
		}
		if (lost || (alive && now >= nextAt)) {
			nextAt = now + (long) (Tune.AUTOSAVE_S * 1000.0);
			server.saveEverything(true, lost, false);
		}
	}

	public static void reset() {
		nextAt = 0L;
		wasAlive = false;
	}
}
