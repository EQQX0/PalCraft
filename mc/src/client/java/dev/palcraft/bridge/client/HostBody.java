package dev.palcraft.bridge.client;

import dev.palcraft.bridge.CoordMap;
import dev.palcraft.bridge.HostBodyServer;
import dev.palcraft.bridge.gen.Tune;
import dev.palcraft.bridge.link.ErLink;
import dev.palcraft.bridge.link.GameState;
import dev.palcraft.bridge.link.Protocol;
import net.minecraft.client.KeyMapping;
import net.minecraft.client.Minecraft;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.client.server.IntegratedServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.entity.Pose;
import net.minecraft.world.phys.Vec3;

/**
 * System "steve_body": Palworld mode. Palworld has the controls and its rules apply, and Steve is drawn where
 * its hidden character stands, so everything Palworld lets a player do happens to Steve on screen.
 *
 * <p>Palworld's own camera leads. Minecraft renders Steve and its blocks from that camera and hands the same
 * pose back, and Palworld shows it once the pixels for it exist: both pictures always share one camera.
 */
public final class HostBody {
	private HostBody() {
	}

	private static final GameState STATE = new GameState();
	private static boolean active;
	private static boolean savedHideGui;
	private static boolean haveLast;
	private static double lastX, lastZ;
	private static Pose pose = Pose.STANDING;
	private static boolean tooClose;
	private static final float[] VITALS = new float[2];
	private static boolean mirrored;

	/** True while Steve's body follows the Palworld character. */
	public static boolean active() {
		return active;
	}

	/** True while a wall holds the camera so close that Steve would fill the picture. */
	public static boolean tooClose() {
		return active && tooClose;
	}

	/** Every frame, after Steve is placed: how far the camera is from the line through his body. */
	static void watchCamera(LocalPlayer p, Vec3 cam) {
		if (p == null) {
			return;
		}
		double dy = cam.y - Math.max(p.getY(), Math.min(p.getY() + p.getBbHeight(), cam.y));
		double dx = cam.x - p.getX(), dz = cam.z - p.getZ();
		double d = Math.sqrt(dx * dx + dy * dy + dz * dz);
		tooClose = d < (tooClose ? Tune.BODY_NEAR_SHOW_M : Tune.BODY_NEAR_HIDE_M);
	}

	/** The pose Steve copies from the Palworld character. */
	public static Pose pose() {
		return pose;
	}

	/** Once per frame, when Overlay knows who has the controls. */
	static void update(Minecraft mc, boolean hostMode, boolean want) {
		HostBodyServer.hostMode = hostMode;
		if (want == active) {
			if (active) {
				// The HUD is Minecraft's in Palworld mode too, except over a shot or screen Palworld shows by itself.
				mc.options.hideGui = savedHideGui || ErLink.get().hudAway();
			}
			return;
		}
		active = want;
		HostBodyServer.following = want;
		haveLast = false;
		tooClose = false;
		pose = Pose.STANDING;
		if (want) {
			savedHideGui = mc.options.hideGui;
			mc.gameRenderer.setRenderHand(false);
			KeyMapping.releaseAll();
		} else {
			mc.options.hideGui = savedHideGui;
			mc.gameRenderer.setRenderHand(true);
			if (mc.player != null) {
				mc.player.deathTime = 0;
				ownVitals(mc, mc.player);
			}
		}
	}

	/**
	 * Palworld mode: the hearts and the hunger bar show the body that takes the hits and gets hungry there, the
	 * Palworld character's. Only this client's copy of Steve changes; his own health and food wait on the server.
	 */
	private static void mirrorVitals(LocalPlayer p) {
		if (!ErLink.get().readVitals(VITALS)) {
			return;
		}
		// Never zero: a client player with no health opens Minecraft's death screen.
		p.setHealth(Math.max(0.01F, Math.min(1.0F, VITALS[0]) * p.getMaxHealth()));
		p.getFoodData().setFoodLevel(Math.round(20.0F * Math.max(0.0F, Math.min(1.0F, VITALS[1]))));
		p.getFoodData().setSaturation(0.0F);
		mirrored = true;
	}

	/** Back in Minecraft mode: Steve's own health and food, as the server kept them. */
	private static void ownVitals(Minecraft mc, LocalPlayer p) {
		if (!mirrored) {
			return;
		}
		mirrored = false;
		IntegratedServer server = mc.getSingleplayerServer();
		ServerPlayer own = server == null ? null : server.getPlayerList().getPlayer(p.getUUID());
		if (own != null) {
			p.setHealth(Math.max(0.01F, own.getHealth()));
			p.getFoodData().setFoodLevel(own.getFoodData().getFoodLevel());
			p.getFoodData().setSaturation(own.getFoodData().getSaturationLevel());
		}
	}

	/** Minecraft yaw of a character whose facing is a quaternion about the up axis. */
	private static float yawOf(float[] q) {
		return (float) (Math.toDegrees(2.0 * Math.atan2(q[1], q[3])) - 180.0);
	}

	/** Every frame, before the level is drawn: Steve stands exactly where the character stood in this state. */
	static void place(Minecraft mc, CoordMap.Mapping map, GameState s, float headPitch) {
		LocalPlayer p = mc.player;
		if (p == null) {
			return;
		}
		Vec3 feet = map.toMc(s.playerPos[0], s.playerPos[1], s.playerPos[2]);
		float yaw = yawOf(s.playerQuat);
		p.setPos(feet.x, feet.y, feet.z);
		p.xo = p.xOld = feet.x;
		p.yo = p.yOld = feet.y;
		p.zo = p.zOld = feet.z;
		p.setYRot(yaw);
		p.yRotO = yaw;
		p.yBodyRot = p.yBodyRotO = yaw;
		p.yHeadRot = p.yHeadRotO = yaw;
		p.setXRot(headPitch);
		p.xRotO = headPitch;
		p.setDeltaMovement(Vec3.ZERO);
	}

	/** Every client tick: Steve's legs move as fast as the character does. */
	static void tick(Minecraft mc) {
		LocalPlayer p = mc.player;
		CoordMap.Mapping map = CoordMap.get();
		if (!active || p == null || map == null || !ErLink.get().snapshot(STATE)
				|| !STATE.has(Protocol.STATE_PLAYER_VALID)) {
			haveLast = false;
			return;
		}
		Vec3 feet = map.toMc(STATE.playerPos[0], STATE.playerPos[1], STATE.playerPos[2]);
		if (haveLast) {
			double dx = feet.x - lastX, dz = feet.z - lastZ;
			p.walkAnimation.update((float) Math.min(1.0, Math.sqrt(dx * dx + dz * dz) * 4.0), 0.4F);
		}
		lastX = feet.x;
		lastZ = feet.z;
		haveLast = true;
		mirrorVitals(p);
		pose = STATE.has(Protocol.STATE_BODY_SWIM) ? Pose.SWIMMING
			: STATE.has(Protocol.STATE_BODY_CROUCH) ? Pose.CROUCHING : Pose.STANDING;
		// Defeated in Palworld: Steve falls the way a Minecraft player does, and gets up when the character does.
		p.deathTime = STATE.has(Protocol.STATE_PLAYER_DEAD) ? Math.min(20, p.deathTime + 1) : 0;
		if (STATE.has(Protocol.STATE_BODY_ACT) && !p.swinging) {
			p.swing(InteractionHand.MAIN_HAND);
		}
	}
}
