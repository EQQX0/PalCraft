package dev.palcraft.bridge.client;

import net.minecraft.client.Minecraft;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.world.phys.AABB;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * System "unstuck": Palworld's ground reaches Minecraft a moment after Steve does. When he flies or falls
 * into a place faster than its rays come back, blocks can appear around his legs and hold him. If he stays
 * inside terrain for half a second, this lifts him to the first free spot above: a ledge when he is in a
 * cave, the hilltop when he flew deep into a hill.
 */
public final class Unstuck {
	private Unstuck() {
	}

	private static final Logger LOG = LoggerFactory.getLogger("palcraft");
	private static final int AFTER_TICKS = 10;
	private static final double NEAR_RISE = 4.0, STEP = 1.0 / 16, MAX_RISE = 96.0, FAR_STEP = 0.5, SKIN = 1e-3;
	private static int stuckTicks;

	public static void tick(Minecraft mc) {
		LocalPlayer player = mc.player;
		if (player == null || mc.level == null || player.isSpectator() || player.isPassenger() || !Overlay.active()) {
			stuckTicks = 0;
			return;
		}
		AABB body = player.getBoundingBox().deflate(SKIN);
		if (mc.level.noCollision(player, body)) {
			stuckTicks = 0;
			return;
		}
		if (++stuckTicks < AFTER_TICKS) {
			return;
		}
		stuckTicks = 0;
		for (double rise = STEP; rise <= MAX_RISE; rise += rise < NEAR_RISE ? STEP : FAR_STEP) {
			if (mc.level.noCollision(player, body.move(0, rise, 0))) {
				player.setPos(player.getX(), player.getY() + rise + SKIN, player.getZ());
				player.setDeltaMovement(player.getDeltaMovement().multiply(1, 0, 1));
				if (rise >= 0.5) {
					LOG.info("Lifted Steve {} m out of terrain that filled in around him", String.format("%.2f", rise));
				}
				return;
			}
		}
	}
}
