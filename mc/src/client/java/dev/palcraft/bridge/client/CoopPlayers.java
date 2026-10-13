package dev.palcraft.bridge.client;

import dev.palcraft.bridge.CoordMap;
import dev.palcraft.bridge.gen.Tune;
import dev.palcraft.bridge.link.ErLink;
import dev.palcraft.bridge.link.PlayerInfo;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.phys.Vec3;

/**
 * System "coop_players": the other players of a Palworld co-op session stand in Minecraft's picture as
 * Minecraft players, in both modes. Palworld lists them; their Palworld bodies are hidden on this PC.
 */
public final class CoopPlayers {
	private CoopPlayers() {
	}

	private static final List<PlayerInfo> ROWS = new ArrayList<>();
	private static final Map<Long, CoopSteve> SHOWN = new HashMap<>();
	private static ClientLevel level;

	/** Friends on screen right now. */
	public static int count() {
		return SHOWN.size();
	}

	private static Vec3 feet(CoordMap.Mapping map, PlayerInfo r) {
		return map.toMc(r.pos[0], r.pos[1], r.pos[2]);
	}

	/** Every client tick: who is there, and how each one stands. */
	static void tick(Minecraft mc) {
		ClientLevel now = mc.level;
		if (now != level) {
			SHOWN.clear();  // they went with their level
			level = now;
		}
		if (now == null) {
			return;
		}
		long ms = System.currentTimeMillis();
		CoordMap.Mapping map = CoordMap.get();
		if (map != null && !map.provisional() && ErLink.get().readPlayers(ROWS, true)) {
			for (PlayerInfo r : ROWS) {
				CoopSteve s = SHOWN.get(r.id);
				if (s != null && !s.shownName.equals(r.name)) {
					now.removeEntity(s.getId(), Entity.RemovalReason.DISCARDED);
					s = null;
				}
				if (s == null) {
					s = new CoopSteve(now, r.id, r.name);
					Vec3 at = feet(map, r);
					s.stand(at, r.yawDeg - 180.0F, -r.pitchDeg);
					s.startAt(at);
					now.addEntity(s);
					SHOWN.put(r.id, s);
				}
				s.report(r, ms);
			}
		}
		for (Iterator<CoopSteve> it = SHOWN.values().iterator(); it.hasNext(); ) {
			CoopSteve s = it.next();
			if (ms - s.seenMs > Tune.PLAYER_GONE_MS) {
				now.removeEntity(s.getId(), Entity.RemovalReason.DISCARDED);
				it.remove();
			}
		}
	}

	/** Every frame, before the level is drawn: each friend stands where their character does now. */
	static void place(CoordMap.Mapping map) {
		if (SHOWN.isEmpty() || !ErLink.get().readPlayers(ROWS, false)) {
			return;
		}
		for (PlayerInfo r : ROWS) {
			CoopSteve s = SHOWN.get(r.id);
			if (s != null) {
				s.stand(feet(map, r), r.yawDeg - 180.0F, -r.pitchDeg);
			}
		}
	}
}
