package dev.palcraft.bridge.client;

import com.mojang.authlib.GameProfile;
import dev.palcraft.bridge.link.PlayerInfo;
import dev.palcraft.bridge.link.Protocol;
import java.util.UUID;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.client.player.RemotePlayer;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.entity.EquipmentSlot;
import net.minecraft.world.entity.Pose;
import net.minecraft.world.phys.Vec3;

/**
 * System "coop_players": a friend in the Palworld session, as a Minecraft player. It lives on this client
 * only; Minecraft's server never hears of it. Palworld decides where it stands and how.
 */
public final class CoopSteve extends RemotePlayer {
	/** Marks the made-up ids of friends, so each keeps the default skin its id picks (DefaultPlayerSkinMixin). */
	public static final long UUID_MSB = 0x50414C4352414654L;

	final String shownName;
	long seenMs;
	private Pose want = Pose.STANDING;
	private String tool = "";
	private double tickX, tickZ;

	CoopSteve(ClientLevel level, long id, String name) {
		super(level, new GameProfile(new UUID(UUID_MSB, id), name.isEmpty() ? "Player" : name));
		shownName = name;
	}

	/** Every client tick: how the friend stands, what they hold, how hurt they are. */
	void report(PlayerInfo r, long nowMs) {
		seenMs = nowMs;
		boolean dead = r.has(Protocol.PLAYER_DEAD);
		want = dead ? Pose.STANDING : r.has(Protocol.PLAYER_SWIM) ? Pose.SWIMMING
			: r.has(Protocol.PLAYER_CROUCH) ? Pose.CROUCHING : Pose.STANDING;
		// Defeated in Palworld: the Minecraft player falls the way one does, and gets up when the character does.
		float health = dead ? 0.0F : Math.max(0.01F, Math.min(1.0F, r.health)) * getMaxHealth();
		if (!dead && getHealth() > 0.0F && health < getHealth() - 0.5F) {
			hurtTime = hurtDuration = 10;
		}
		setHealth(health);
		if (!dead) {
			deathTime = 0;
		}
		if (r.has(Protocol.PLAYER_ACT) && !dead && !swinging) {
			swing(InteractionHand.MAIN_HAND);
		}
		if (!r.tool.equals(tool)) {
			tool = r.tool;
			setItemSlot(EquipmentSlot.MAINHAND, LoadoutHud.stackFor(tool));
		}
	}

	/** Every frame, before the level is drawn: exactly where the Palworld character stands now. */
	void stand(Vec3 feet, float yaw, float pitch) {
		setPos(feet.x, feet.y, feet.z);
		xo = xOld = feet.x;
		yo = yOld = feet.y;
		zo = zOld = feet.z;
		setYRot(yaw);
		yRotO = yaw;
		yBodyRot = yBodyRotO = yaw;
		yHeadRot = yHeadRotO = yaw;
		setXRot(pitch);
		xRotO = pitch;
		setDeltaMovement(Vec3.ZERO);
	}

	void startAt(Vec3 feet) {
		tickX = feet.x;
		tickZ = feet.z;
	}

	@Override
	protected void updatePlayerPose() {
		setPose(want);
	}

	/** The legs move as fast as the character does: stand() leaves no old position for Minecraft to measure. */
	@Override
	public void calculateEntityAnimation(boolean includeHeight) {
		double dx = getX() - tickX, dz = getZ() - tickZ;
		tickX = getX();
		tickZ = getZ();
		walkAnimation.update((float) Math.min(1.0, Math.sqrt(dx * dx + dz * dz) * 4.0), 0.4F);
	}

	@Override
	public boolean isPushable() {
		return false;
	}

	@Override
	protected void pushEntities() {
	}
}
