package dev.palcraft.bridge;

import dev.palcraft.bridge.gen.Tune;
import dev.palcraft.bridge.link.ErLink;
import net.minecraft.core.BlockPos;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.tags.BlockTags;
import net.minecraft.tags.FluidTags;
import net.minecraft.tags.ItemTags;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.properties.BlockStateProperties;

/**
 * System "body_warmth": one body, two games. Steve's food level goes to Palworld, where it becomes the hidden
 * character's stomach. The Minecraft blocks around him count as warmth there too: a campfire he builds
 * keeps Palworld's night cold off, and standing in his own water cools a desert day.
 */
public final class BodyBridge {
	private BodyBridge() {
	}

	private static final int[] BODY = new int[3];
	private static int warmth;

	public static void onServerTick(MinecraftServer server) {
		if (!TerrainManager.isBridgeWorld() || server.getPlayerList().getPlayers().isEmpty()) {
			return;
		}
		ServerPlayer player = server.getPlayerList().getPlayers().get(0);
		ServerLevel level = player.serverLevel();
		if (level.getGameTime() % 20 == 0) {
			warmth = player.isAlive() ? warmth(level, player) : 0;
			ErLink.get().writeBody(player.getFoodData().getFoodLevel(), warmth);
		}
		// Palworld's cold shows the way Minecraft shows it: frost creeping in from the edges of the screen.
		if (player.isAlive() && !player.isCreative() && !player.isSpectator() && ErLink.get().readBody(BODY) && BODY[0] < -BODY[2]) {
			player.setTicksFrozen(Math.min(110, player.getTicksFrozen() + 4));
		}
	}

	/**
	 * +2 open fire or lava, +1 a torch or lit furnace close by or a torch in hand, -1 in water or beside ice.
	 * Leather keeps the cold off as it does in powder snow: +1 for a piece, +2 for the whole set, unless he is wet.
	 */
	private static int warmth(ServerLevel level, ServerPlayer player) {
		int leather = 0;
		for (ItemStack worn : player.getArmorSlots()) {
			leather += worn.is(ItemTags.FREEZE_IMMUNE_WEARABLES) ? 1 : 0;
		}
		leather = leather >= 4 ? 2 : Math.min(1, leather);
		if (player.isOnFire()) {
			return 2 + leather;
		}
		int r = (int) Tune.WARMTH_RADIUS;
		BlockPos feet = player.blockPosition();
		boolean near = false, cool = player.isInWater();
		for (BlockPos pos : BlockPos.betweenClosed(feet.offset(-r, -2, -r), feet.offset(r, 3, r))) {
			BlockState state = level.getBlockState(pos);
			if (state.isAir() || ErBridgeMod.isTerrain(state)) {
				continue;
			}
			boolean lit = !state.hasProperty(BlockStateProperties.LIT) || state.getValue(BlockStateProperties.LIT);
			if (state.is(BlockTags.FIRE) || state.is(BlockTags.CAMPFIRES) && lit || state.is(Blocks.MAGMA_BLOCK)
					|| state.getFluidState().is(FluidTags.LAVA)) {
				return 2 + leather;
			}
			if (pos.distManhattan(feet) <= 4) {
				near |= state.is(Blocks.TORCH) || state.is(Blocks.WALL_TORCH) || state.is(Blocks.LANTERN)
					|| state.is(Blocks.JACK_O_LANTERN) || state.hasProperty(BlockStateProperties.LIT) && lit;
				cool |= state.is(BlockTags.ICE) || state.is(Blocks.SNOW_BLOCK) || state.is(Blocks.POWDER_SNOW);
			}
		}
		if (near || torch(player.getMainHandItem()) || torch(player.getOffhandItem())) {
			return 1 + leather;
		}
		return cool ? -1 : leather;
	}

	private static boolean torch(ItemStack stack) {
		return stack.is(Items.TORCH) || stack.is(Items.LANTERN) || stack.is(Items.LAVA_BUCKET);
	}
}
