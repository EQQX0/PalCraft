package dev.palcraft.bridge;

import dev.palcraft.bridge.gen.Loot;
import dev.palcraft.bridge.gen.Tune;
import dev.palcraft.bridge.link.ErLink;
import dev.palcraft.bridge.link.Protocol;
import io.netty.buffer.ByteBuf;
import net.fabricmc.fabric.api.networking.v1.PayloadTypeRegistry;
import net.fabricmc.fabric.api.networking.v1.ServerPlayNetworking;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.BlockParticleOption;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.network.chat.Component;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.tags.ItemTags;
import net.minecraft.world.entity.EquipmentSlot;
import net.minecraft.world.entity.ExperienceOrb;
import net.minecraft.world.entity.item.ItemEntity;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.TieredItem;
import net.minecraft.world.item.Tiers;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.HitResult;
import net.minecraft.world.phys.Vec3;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

/**
 * System "gather": survival on Palworld's islands. Palworld's ground, cliffs and trees cannot be removed,
 * so Steve digs them instead: hold attack on the world and materials come out. Palworld says what the
 * crosshair is on (system "surface_probe"); sheets/gather.json says what that surface gives to which tool.
 */
public final class Gather {
	private Gather() {
	}

	private static final Logger LOG = LoggerFactory.getLogger("palcraft");

	/** Client to server: "I finished digging at this terrain block". */
	public record DigPayload(BlockPos pos) implements CustomPacketPayload {
		public static final Type<DigPayload> TYPE = new Type<>(ResourceLocation.fromNamespaceAndPath(ErBridgeMod.MOD_ID, "dig"));
		public static final StreamCodec<ByteBuf, DigPayload> CODEC = BlockPos.STREAM_CODEC.map(DigPayload::new, DigPayload::pos);

		@Override
		public Type<? extends CustomPacketPayload> type() {
			return TYPE;
		}
	}

	private record Pending(UUID player, BlockPos pos, Vec3 at, int seq, long since) {
	}

	private static Pending pending;
	private static final Map<UUID, Long> LAST_DIG = new HashMap<>();
	/** Dug spots and the game time they yield again. */
	private static final Map<Long, Long> SPENT = new HashMap<>();

	public static void register() {
		PayloadTypeRegistry.playC2S().register(DigPayload.TYPE, DigPayload.CODEC);
		ServerPlayNetworking.registerGlobalReceiver(DigPayload.TYPE,
			(payload, context) -> context.server().execute(() -> dig(context.player(), payload.pos())));
	}

	/** 0 hand, wood or gold; 1 stone; 2 iron; 3 diamond; 4 netherite. -1: the stack is no tool. */
	public static int tier(ItemStack stack) {
		if (!(stack.getItem() instanceof TieredItem tiered) || toolKind(stack).equals("hand")) {
			return -1;
		}
		if (tiered.getTier() instanceof Tiers t) {
			return switch (t) {
				case STONE -> 1;
				case IRON -> 2;
				case DIAMOND -> 3;
				case NETHERITE -> 4;
				default -> 0;
			};
		}
		return 2; // another mod's tool: treat it as iron
	}

	public static String toolKind(ItemStack stack) {
		if (stack.is(ItemTags.PICKAXES)) return "pickaxe";
		if (stack.is(ItemTags.AXES)) return "axe";
		if (stack.is(ItemTags.SHOVELS)) return "shovel";
		if (stack.is(ItemTags.HOES)) return "hoe";
		return "hand";
	}

	/** Ticks of holding attack for one dig with this stack in hand. */
	public static int digTicks(ItemStack stack) {
		int tier = tier(stack);
		if (tier < 0) {
			return (int) Tune.DIG_TICKS_HAND;
		}
		boolean gold = stack.getItem() instanceof TieredItem t && t.getTier() == Tiers.GOLD;
		return gold ? 10 : switch (tier) {
			case 0 -> 26;
			case 1 -> 20;
			case 2 -> 14;
			case 3 -> 10;
			default -> 8;
		};
	}

	private static void dig(ServerPlayer player, BlockPos pos) {
		ServerLevel level = player.serverLevel();
		long now = level.getGameTime();
		CoordMap.Mapping map = CoordMap.get();
		if (!TerrainManager.isBridgeWorld() || map == null || map.provisional() || pending != null
				|| !player.isAlive() || player.isSpectator() || !ErBridgeMod.isTerrain(level.getBlockState(pos))
				|| now - LAST_DIG.getOrDefault(player.getUUID(), 0L) < 5) {
			return;
		}
		double reach = player.blockInteractionRange();
		Vec3 eye = player.getEyePosition();
		if (eye.distanceToSqr(Vec3.atCenterOf(pos)) > (reach + 2) * (reach + 2)) {
			return;
		}
		Long again = SPENT.get(pos.asLong());
		if (again != null && again > now) {
			player.displayClientMessage(Component.translatable("palcraft.gather.spent"), true);
			return;
		}
		// The terrain block can start a little before Palworld's real surface: trace the whole reach there.
		Vec3 end = eye.add(player.getViewVector(1.0F).scale(reach + 1.5));
		double[] a = map.toHost(eye.x, eye.y, eye.z), b = map.toHost(end.x, end.y, end.z);
		int seq = ErLink.get().submitProbe(new float[] {(float) a[0], (float) a[1], (float) a[2], (float) b[0], (float) b[1], (float) b[2]});
		if (seq < 0) {
			return;
		}
		HitResult hit = player.pick(reach, 1.0F, false);
		Vec3 at = hit.getType() == HitResult.Type.MISS ? Vec3.atCenterOf(pos) : hit.getLocation();
		pending = new Pending(player.getUUID(), pos.immutable(), at, seq, now);
		LAST_DIG.put(player.getUUID(), now);
	}

	public static void onServerTick(MinecraftServer server) {
		if (pending == null) {
			return;
		}
		Pending p = pending;
		ServerLevel level = server.overworld();
		int kind = ErLink.get().probeKind(p.seq());
		if (kind < 0) {
			if (level.getGameTime() - p.since() > 30) {
				ErLink.get().abandonProbe();
				pending = null;
			}
			return;
		}
		pending = null;
		ServerPlayer player = server.getPlayerList().getPlayer(p.player());
		if (player != null && player.isAlive()) {
			drop(level, player, p, kind);
		}
	}

	private static void drop(ServerLevel level, ServerPlayer player, Pending p, int kind) {
		if (kind == Protocol.SURFACE_NONE) {
			return;
		}
		ItemStack tool = player.getMainHandItem();
		String held = toolKind(tool);
		int tier = Math.max(0, tier(tool));
		Vec3 eye = player.getEyePosition();
		Vec3 out = p.at().add(eye.subtract(p.at()).normalize().scale(0.4));
		int rows = 0, xp = 0;
		for (Object[] row : Loot.GATHER) {
			if ((int) row[0] != kind || !(row[1].equals("any") || row[1].equals(held)) || tier < (int) row[2]) {
				continue;
			}
			rows++;
			if (level.random.nextDouble() >= (double) row[6]) {
				continue;
			}
			int count = (int) row[4] + level.random.nextInt((int) row[5] - (int) row[4] + 1);
			ItemStack stack = new ItemStack(BuiltInRegistries.ITEM.get(ResourceLocation.parse((String) row[3])), count);
			if (stack.isEmpty()) {
				continue;
			}
			ItemEntity item = new ItemEntity(level, out.x, out.y, out.z, stack);
			item.setDefaultPickUpDelay();
			level.addFreshEntity(item);
			xp += (int) row[7];
		}
		if (rows == 0) {
			player.displayClientMessage(Component.translatable(kind == Protocol.SURFACE_STONE || kind == Protocol.SURFACE_ORE
				? "palcraft.gather.needs_pickaxe" : "palcraft.gather.nothing"), true);
			return;
		}
		if (xp > 0) {
			ExperienceOrb.award(level, out, xp);
		}
		level.playSound(null, p.pos(), sound(kind), SoundSource.BLOCKS, 1.0F, 0.9F);
		level.sendParticles(new BlockParticleOption(ParticleTypes.BLOCK, look(kind)), p.at().x, p.at().y, p.at().z, 16, 0.25, 0.25, 0.25, 0.05);
		if (tool.isDamageableItem() && !held.equals("hand")) {
			tool.hurtAndBreak(1, player, EquipmentSlot.MAINHAND);
		}
		player.causeFoodExhaustion(0.005F);
		long now = level.getGameTime();
		if (SPENT.size() > 4096) {
			SPENT.values().removeIf(t -> t <= now);
		}
		SPENT.put(p.pos().asLong(), now + (long) (Tune.DIG_RESPAWN_S * 20));
	}

	private static SoundEvent sound(int kind) {
		return switch (kind) {
			case Protocol.SURFACE_WOOD -> SoundEvents.WOOD_BREAK;
			case Protocol.SURFACE_SAND -> SoundEvents.SAND_BREAK;
			case Protocol.SURFACE_SNOW -> SoundEvents.SNOW_BREAK;
			case Protocol.SURFACE_GRASS -> SoundEvents.GRASS_BREAK;
			case Protocol.SURFACE_SOIL -> SoundEvents.GRAVEL_BREAK;
			default -> SoundEvents.STONE_BREAK;
		};
	}

	private static BlockState look(int kind) {
		return (switch (kind) {
			case Protocol.SURFACE_WOOD -> Blocks.OAK_LOG;
			case Protocol.SURFACE_SAND -> Blocks.SAND;
			case Protocol.SURFACE_SNOW -> Blocks.SNOW_BLOCK;
			case Protocol.SURFACE_GRASS -> Blocks.GRASS_BLOCK;
			case Protocol.SURFACE_SOIL -> Blocks.DIRT;
			case Protocol.SURFACE_ORE -> Blocks.IRON_ORE;
			default -> Blocks.STONE;
		}).defaultBlockState();
	}

	public static void reset() {
		pending = null;
		LAST_DIG.clear();
		SPENT.clear();
	}
}
