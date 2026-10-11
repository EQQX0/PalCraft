package dev.palcraft.bridge.entity;

import dev.palcraft.bridge.gen.Loot;
import dev.palcraft.bridge.link.Protocol;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.entity.ExperienceOrb;
import net.minecraft.world.entity.item.ItemEntity;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.phys.Vec3;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

/**
 * System "pal_loot": a Pal that Steve kills drops Minecraft items and experience where it fell, so hunting
 * feeds him and his farm. sheets/pal_loot.json lists the drops by Palworld character id; its "!boss" rows are
 * for alphas and tower bosses.
 */
public final class PalLoot {
	private PalLoot() {
	}

	private static final Logger LOG = LoggerFactory.getLogger("palcraft");
	private static final long CREDIT_TICKS = 1200;
	/** Palworld id of a Pal, and the game time of Steve's last hit on it. */
	private static final Map<Long, Long> HIT = new HashMap<>();

	public static void hitByPlayer(long hostId, long gameTime) {
		if (HIT.size() > 512) {
			HIT.values().removeIf(t -> gameTime - t > CREDIT_TICKS);
		}
		HIT.put(hostId, gameTime);
	}

	/**
	 * The proxy is leaving the world. died: Palworld listed the Pal as dead. A Pal can also die and drop
	 * off Palworld's list between two reads; one that Steve had beaten down to a sliver counts as his kill.
	 */
	public static void gone(ServerLevel level, ErEntity proxy, boolean died) {
		Long hit = HIT.remove(proxy.hostId());
		if (hit == null || level.getGameTime() - hit > CREDIT_TICKS) {
			return;
		}
		if (!died && !(proxy.maxHp() > 0 && proxy.hp() <= proxy.maxHp() * 0.12F)) {
			return;
		}
		String id = proxy.getName().getString().toLowerCase(Locale.ROOT);
		Vec3 at = proxy.position().add(0, 0.3, 0);
		int stacks = 0;
		for (Object[] row : Loot.PALS) {
			String match = (String) row[0];
			boolean fits = match.equals("!boss") ? proxy.kind() == Protocol.ENT_LARGE_MONSTER : match.equals("*") || id.contains(match);
			if (!fits || level.random.nextDouble() >= (double) row[4]) {
				continue;
			}
			int count = (int) row[2] + level.random.nextInt((int) row[3] - (int) row[2] + 1);
			ItemStack stack = new ItemStack(BuiltInRegistries.ITEM.get(ResourceLocation.parse((String) row[1])), count);
			if (stack.isEmpty()) {
				continue;
			}
			ItemEntity item = new ItemEntity(level, at.x, at.y, at.z, stack);
			item.setDefaultPickUpDelay();
			level.addFreshEntity(item);
			stacks++;
		}
		ExperienceOrb.award(level, at, Math.min(20, 3 + (int) (proxy.maxHp() / 150)));
		LOG.info("Steve's kill {} dropped {} stacks", proxy.getName().getString(), stacks);
	}

	public static void reset() {
		HIT.clear();
	}
}
