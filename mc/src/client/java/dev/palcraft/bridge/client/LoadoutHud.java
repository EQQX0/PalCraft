package dev.palcraft.bridge.client;

import com.mojang.blaze3d.systems.RenderSystem;
import dev.palcraft.bridge.gen.Loadout;
import dev.palcraft.bridge.link.ErLink;
import java.util.Arrays;
import java.util.Locale;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;

/**
 * System "loadout_hotbar": Palworld mode's hotbar. Palworld's tools do the work there, so the hotbar shows
 * them: the tools of its weapon slots as Minecraft items, in the slots its number keys pick, and the selected
 * Pal Sphere with its count in the last slot. Steve's own items wait in his inventory.
 */
public final class LoadoutHud {
	private LoadoutHud() {
	}

	private static final ResourceLocation HOTBAR = ResourceLocation.withDefaultNamespace("hud/hotbar");
	private static final ResourceLocation SELECTION = ResourceLocation.withDefaultNamespace("hud/hotbar_selection");
	private static final int SLOTS = 9;
	/** The tool slot in hand, spheres carried, rounds loaded (-1 = none), rounds carried. */
	private static final int[] NUM = {-1, 0, -1, 0};
	private static final ItemStack[] STACKS = new ItemStack[SLOTS];
	private static String lastTools = "", lastBall = "";
	private static int tools;

	static {
		Arrays.fill(STACKS, ItemStack.EMPTY);
	}

	static void tick(Minecraft mc) {
		if (!HostBody.active()) {
			return;
		}
		ErLink link = ErLink.get();
		if (!link.readLoadout(NUM)) {
			return;
		}
		String names = link.loadout(), ball = link.ball();
		if (names.equals(lastTools) && ball.equals(lastBall)) {
			return;
		}
		lastTools = names;
		lastBall = ball;
		Arrays.fill(STACKS, ItemStack.EMPTY);
		String[] each = names.isEmpty() ? new String[0] : names.split("\\|", -1);
		tools = Math.min(each.length, SLOTS - 1);
		for (int i = 0; i < tools; i++) {
			if (!each[i].isEmpty()) {
				STACKS[i] = new ItemStack(item(each[i]));
			}
		}
		if (!ball.isEmpty()) {
			STACKS[SLOTS - 1] = new ItemStack(item(ball));
		}
	}

	/** The Minecraft item that stands for a Palworld tool or sphere (sheets/tools.json). */
	private static Item item(String palworld) {
		String name = palworld.toLowerCase(Locale.ROOT);
		for (String[] row : Loadout.TOOLS) {
			if (row[0].equals("*") || name.contains(row[0])) {
				Item item = BuiltInRegistries.ITEM.get(ResourceLocation.parse(row[1]));
				return item == Items.AIR ? Items.STICK : item;
			}
		}
		return Items.STICK;
	}

	/** Drawn in place of Minecraft's own hotbar, the way Minecraft draws that. */
	public static void render(Minecraft mc, GuiGraphics g) {
		int middle = g.guiWidth() / 2, bottom = g.guiHeight();
		boolean sphere = NUM[1] > 0 && !STACKS[SLOTS - 1].isEmpty();
		// Palworld counts the sphere in hand as the slot after its weapon slots.
		int held = NUM[0] < 0 ? -1 : NUM[0] < tools ? NUM[0] : sphere ? SLOTS - 1 : -1;
		RenderSystem.enableBlend();
		g.pose().pushPose();
		g.pose().translate(0.0F, 0.0F, -90.0F);
		g.blitSprite(HOTBAR, middle - 91, bottom - 22, 182, 22);
		if (held >= 0) {
			g.blitSprite(SELECTION, middle - 91 - 1 + held * 20, bottom - 22 - 1, 24, 23);
		}
		g.pose().popPose();
		RenderSystem.disableBlend();
		for (int i = 0; i < SLOTS; i++) {
			ItemStack stack = STACKS[i];
			if (stack.isEmpty() || (i == SLOTS - 1 && !sphere)) {
				continue;
			}
			int x = middle - 90 + i * 20 + 2, y = bottom - 16 - 3;
			String count = i == SLOTS - 1 ? String.valueOf(NUM[1]) : i == held && NUM[2] >= 0 ? String.valueOf(NUM[2]) : null;
			g.renderItem(stack, x, y);
			g.renderItemDecorations(mc.font, stack, x, y, count);
		}
		if (held >= 0 && held < tools && NUM[2] >= 0) {
			g.drawString(mc.font, "+" + NUM[3], middle + 91 + 4, bottom - 14, 0xFFFFFF, true);
		}
	}
}
