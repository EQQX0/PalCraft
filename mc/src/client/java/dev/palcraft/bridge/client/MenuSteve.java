package dev.palcraft.bridge.client;

import dev.palcraft.bridge.gen.Tune;
import dev.palcraft.bridge.link.ErLink;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.screens.inventory.InventoryScreen;
import net.minecraft.client.player.LocalPlayer;

/**
 * System "menu_steve": Palworld's inventory screen shows the character in the middle. In Palworld mode that
 * character is Steve, so Palworld fades its own preview and Minecraft draws him there, the way its own
 * inventory screen shows him. Palworld draws its screens over Minecraft's picture: the compositor is told
 * where he stands and puts that part on top.
 */
public final class MenuSteve {
	private MenuSteve() {
	}

	private static boolean told;

	/** The inventory screen is gone: nothing of Minecraft's goes over Palworld's interface. */
	static void gone() {
		if (told) {
			ErLink.get().writePreviewRect(0.0F, 0.0F, 0.0F, 0.0F);
			told = false;
		}
	}

	public static void render(Minecraft mc, GuiGraphics g) {
		LocalPlayer player = mc.player;
		if (player == null) {
			return;
		}
		int height = g.guiHeight();
		int middle = g.guiWidth() / 2 + (int) Math.round(Tune.PREVIEW_CENTER_X * height);
		int top = (int) Math.round(Tune.PREVIEW_TOP * height), bottom = (int) Math.round(Tune.PREVIEW_BOTTOM * height);
		int half = (bottom - top) / 3;
		int scale = (int) ((bottom - top) / 2.15);
		// He looks a little to his right and down, as in Minecraft's inventory with the pointer beside him.
		float lookX = middle + half * 0.6F, lookY = top + (bottom - top) * 0.3F;
		int fallen = player.deathTime;
		player.deathTime = 0;
		InventoryScreen.renderEntityInInventoryFollowsMouse(g, middle - half, top, middle + half, bottom, scale, 0.0625F,
			lookX, lookY, player);
		player.deathTime = fallen;
		float w = g.guiWidth(), h = height;
		ErLink.get().writePreviewRect((middle - half) / w, top / h, (middle + half) / w, bottom / h);
		told = true;
	}
}
