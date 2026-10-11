package dev.palcraft.bridge;

import dev.palcraft.bridge.gen.Kit;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;

/**
 * System "starter_kit": the stacks in sheets/kit.json, given once per player in the PalCraft world. A row's
 * wave says which kit version added it, so a player who holds an older kit gets only what is new.
 */
public final class StarterKit {
	private StarterKit() {
	}

	private static String tag(int wave) {
		return wave == 1 ? "palcraft_kit" : "palcraft_kit_" + wave;
	}

	public static void onJoin(ServerPlayer player) {
		if (!TerrainManager.isBridgeWorld()) {
			return;
		}
		boolean fresh = !player.getTags().contains(tag(1));
		for (Object[] row : Kit.STACKS) {
			if (player.getTags().contains(tag((Integer) row[3]))) {
				continue;
			}
			int slot = (Integer) row[0];
			Item item = BuiltInRegistries.ITEM.get(ResourceLocation.parse((String) row[1]));
			if (item == Items.AIR) {
				continue;
			}
			ItemStack stack = new ItemStack(item, (Integer) row[2]);
			if (fresh && player.getInventory().getItem(slot).isEmpty()) {
				player.getInventory().setItem(slot, stack);
			} else if (!player.getInventory().add(stack)) {
				player.drop(stack, false);
			}
		}
		for (int wave = 1; wave <= Kit.WAVES; wave++) {
			player.addTag(tag(wave));
		}
	}
}
