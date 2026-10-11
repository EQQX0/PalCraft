package dev.palcraft.bridge;

import dev.palcraft.bridge.gen.Kit;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;

/** System "starter_kit": the stacks in sheets/kit.json, given once per player in the PalCraft world. */
public final class StarterKit {
	private StarterKit() {
	}

	private static final String GIVEN = "palcraft_kit";

	public static void onJoin(ServerPlayer player) {
		if (!TerrainManager.isBridgeWorld() || player.getTags().contains(GIVEN)) {
			return;
		}
		for (Object[] row : Kit.STACKS) {
			int slot = (Integer) row[0];
			Item item = BuiltInRegistries.ITEM.get(ResourceLocation.parse((String) row[1]));
			if (item == Items.AIR) {
				continue;
			}
			ItemStack stack = new ItemStack(item, (Integer) row[2]);
			if (player.getInventory().getItem(slot).isEmpty()) {
				player.getInventory().setItem(slot, stack);
			} else {
				player.getInventory().add(stack);
			}
		}
		player.addTag(GIVEN);
	}
}
