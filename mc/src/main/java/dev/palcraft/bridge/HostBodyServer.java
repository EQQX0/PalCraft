package dev.palcraft.bridge;

import dev.palcraft.bridge.link.ErLink;
import dev.palcraft.bridge.link.GameState;
import dev.palcraft.bridge.link.Protocol;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.phys.Vec3;

/**
 * Server half of system "steve_body". While Palworld has the controls, Steve stands wherever its character
 * does: the server moves him there itself (the client sends no moves meanwhile), so chunks, blocks and Pal
 * hitboxes stay loaded around him. Palworld's rules own his life in that mode.
 */
public final class HostBodyServer {
	private HostBodyServer() {
	}

	/** Palworld has keyboard and mouse (set by the client; single player shares the JVM). */
	public static volatile boolean hostMode;
	/** Steve's body is being drawn at the Palworld character. */
	public static volatile boolean following;

	private static final GameState STATE = new GameState();

	public static void onServerTick(MinecraftServer server) {
		if (!following || !TerrainManager.isBridgeWorld()) {
			return;
		}
		CoordMap.Mapping map = CoordMap.get();
		ErLink link = ErLink.get();
		if (map == null || map.provisional() || !link.alive() || !link.snapshot(STATE)
				|| !STATE.has(Protocol.STATE_PLAYER_VALID) || map.zone() != STATE.stageId) {
			return;
		}
		Vec3 feet = map.toMc(STATE.playerPos[0], STATE.playerPos[1], STATE.playerPos[2]);
		for (ServerPlayer player : server.getPlayerList().getPlayers()) {
			if (player.isAlive()) {
				player.moveTo(feet.x, feet.y, feet.z, player.getYRot(), player.getXRot());
				player.setDeltaMovement(Vec3.ZERO);
				player.fallDistance = 0.0F;
			}
		}
	}

	public static void reset() {
		hostMode = false;
		following = false;
	}
}
