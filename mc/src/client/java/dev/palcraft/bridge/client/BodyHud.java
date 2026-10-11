package dev.palcraft.bridge.client;

import dev.palcraft.bridge.link.ErLink;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.tags.FluidTags;

/**
 * System "body_hud": Palworld's body temperature as a gauge above Steve's hunger bar. Nine cells run from
 * deep cold on the left to burning on the right; the bright one is where he is now, and the green line marks
 * what his clothes take. Outside that line the gauge blinks and Palworld's cold or heat costs him hearts.
 */
public final class BodyHud {
	private BodyHud() {
	}

	private static final int CELLS = 9, CELL_W = 8, GAP = 1, CELL_H = 5;
	private static final int[] COLORS = {
		0xFF2456D6, 0xFF3B7BEA, 0xFF63A4F4, 0xFF9CCBF7, 0xFFD8D8D8, 0xFFF7CF8A, 0xFFF4A04A, 0xFFE9682C, 0xFFD63A24};
	private static final int[] BODY = new int[3];
	private static boolean valid;
	private static int ticks;

	public static void tick(Minecraft mc) {
		if (++ticks % 10 == 0) {
			valid = mc.level != null && ErLink.get().readBody(BODY);
		}
	}

	public static void render(Minecraft mc, GuiGraphics g) {
		LocalPlayer player = mc.player;
		if (!valid || player == null || mc.options.hideGui || mc.gameMode == null || !mc.gameMode.canHurtPlayer()) {
			return;
		}
		int temperature = BODY[0], heat = Math.max(0, BODY[1]), cold = Math.max(0, BODY[2]);
		boolean air = player.isEyeInFluid(FluidTags.WATER) || player.getAirSupply() < player.getMaxAirSupply();
		int x0 = g.guiWidth() / 2 + 10;
		int y = g.guiHeight() - 39 - 8 - (air ? 10 : 0);
		int now = Math.max(-4, Math.min(4, temperature)) + 4;
		boolean harm = temperature > heat || temperature < -cold;
		boolean blink = harm && (ticks / 6) % 2 == 0;
		// Chat lines reach across the hunger bar and sit nearer the eye than this callback draws: come forward,
		// or the last chat line swallows the gauge.
		g.pose().pushPose();
		g.pose().translate(0.0F, 0.0F, 4000.0F);
		for (int i = 0; i < CELLS; i++) {
			int x = x0 + i * (CELL_W + GAP);
			int level = i - 4;
			g.fill(x, y, x + CELL_W, y + CELL_H, 0xFF101010);
			int color = COLORS[i];
			if (i != now) {
				color = 0xFF000000 | ((color >> 16 & 0xFF) * 2 / 5) << 16 | ((color >> 8 & 0xFF) * 2 / 5) << 8 | (color & 0xFF) * 2 / 5;
			}
			g.fill(x + 1, y + 1, x + CELL_W - 1, y + CELL_H - 1, color);
			if (level >= -cold && level <= heat) {
				g.fill(x, y + CELL_H, x + CELL_W, y + CELL_H + 1, 0xFF4CC24C);
			}
			if (i == now) {
				int frame = blink ? (temperature < 0 ? 0xFF7FD4FF : 0xFFFF5A3C) : 0xFFFFFFFF;
				g.fill(x - 1, y - 1, x + CELL_W + 1, y, frame);
				g.fill(x - 1, y + CELL_H, x + CELL_W + 1, y + CELL_H + 1, frame);
				g.fill(x - 1, y, x, y + CELL_H, frame);
				g.fill(x + CELL_W, y, x + CELL_W + 1, y + CELL_H, frame);
			}
		}
		g.pose().popPose();
	}
}
