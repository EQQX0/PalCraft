package dev.palcraft.bridge.client;

import dev.palcraft.bridge.CoordMap;
import dev.palcraft.bridge.link.ControlState;
import dev.palcraft.bridge.link.GameState;
import dev.palcraft.bridge.link.ErLink;
import dev.palcraft.bridge.link.Protocol;
import net.minecraft.client.Camera;
import net.minecraft.client.Minecraft;
import net.minecraft.world.phys.Vec3;
import org.joml.Vector3f;

/**
 * Keeps the two cameras identical so Minecraft's layer lines up with the host game's frame.
 *
 * <ul>
 *   <li>FOLLOW_HOST: Minecraft renders from the host game's camera (it stays in charge). Needs
 *   only read access to its camera; used to verify alignment.</li>
 *   <li>DRIVE_HOST: the host game renders from Minecraft's camera, so the Minecraft player can
 *   walk around its world. Needs the DLL's camera override.</li>
 * </ul>
 */
public final class CameraSync {
	private CameraSync() {
	}

	public enum Mode {
		FOLLOW_HOST,
		DRIVE_HOST
	}

	public interface CameraAccess {
		void palcraft$setPosition(Vec3 pos);

		void palcraft$setRotation(float yaw, float pitch);

		/** Detached = the camera is not in the player's head, so the player's own body is drawn. */
		void palcraft$setDetached(boolean value);
	}

	private static Mode mode = Mode.DRIVE_HOST;
	/** The hunter follows the Minecraft player (hidden) and takes the host game's hits for it. */
	private static boolean standIn = true;
	/** Debug knobs for the in-host-game compositor (see dev commands "pt ..."). */
	public static int poseLag = 1;
	public static int depthIndex = 0;
	public static boolean noDepthTest;
	public static boolean debugDepth;
	private static final GameState STATE = new GameState();
	private static final ControlState CONTROL = new ControlState();
	private static float fov = 70.0F;
	private static boolean controlling;

	public static Mode mode() {
		return mode;
	}

	public static void toggleMode() {
		mode = mode == Mode.FOLLOW_HOST ? Mode.DRIVE_HOST : Mode.FOLLOW_HOST;
	}

	/** True when the Minecraft player may drive the host game (right zone, already placed at the hunter). */
	private static boolean ready(Minecraft mc, CoordMap.Mapping map) {
		if (map.provisional() || !STATE.has(Protocol.STATE_PLAYER_VALID) || map.zone() != STATE.stageId) {
			return false;  // the server hasn't switched to this host-game zone yet
		}
		if (mc.player == null || !map.contains(mc.player.getX())) {
			return false;  // teleport into this zone's region not received yet
		}
		// Whenever the Palworld character is the truth (control back from Palworld, a respawn on either
		// side, a warp), keep our hands off its camera and body until the server has moved the
		// Minecraft player to it and the teleport has reached this client.
		return dev.palcraft.bridge.TerrainManager.recallSettled(400);
	}

	public static boolean toggleStandIn() {
		standIn = !standIn;
		return standIn;
	}

	/** Field of view Minecraft must render with while the overlay is active. */
	public static float fov() {
		return fov;
	}

	/** True once the host game confirmed it rendered with our camera. */
	public static boolean hostFollowing() {
		return STATE.has(Protocol.STATE_CAM_OVERRIDDEN);
	}

	private static boolean driving;

	/** True while Minecraft's camera is driving the host game's this frame. */
	public static boolean driving() {
		return driving;
	}

	/** True while the host game draws our frames into its own image. */
	public static boolean hostCompositing() {
		return STATE.has(Protocol.STATE_COMPOSITING);
	}

	public static void copyCurrentPose(ControlState out) {
		out.flags = CONTROL.flags;
		out.fovYDeg = CONTROL.fovYDeg;
		out.poseLag = CONTROL.poseLag;
		out.depthIndex = CONTROL.depthIndex;
		System.arraycopy(CONTROL.camPos, 0, out.camPos, 0, 3);
		System.arraycopy(CONTROL.camTarget, 0, out.camTarget, 0, 3);
		System.arraycopy(CONTROL.camUp, 0, out.camUp, 0, 3);
		System.arraycopy(CONTROL.hunterPos, 0, out.hunterPos, 0, 3);
		out.hunterYawDeg = CONTROL.hunterYawDeg;
		out.supportEpoch = CONTROL.supportEpoch;
		out.supportTravelY = CONTROL.supportTravelY;
	}

	public static void afterCameraSetup(Camera camera) {
		Minecraft mc = Minecraft.getInstance();
		CoordMap.Mapping map = CoordMap.get();
		boolean haveState = ErLink.get().snapshot(STATE);
		if (HostBody.active() && map != null && haveState && STATE.has(Protocol.STATE_CAMERA_VALID)
				&& STATE.has(Protocol.STATE_PLAYER_VALID) && !map.provisional() && map.zone() == STATE.stageId) {
			followHostBody(mc, map, camera);
			return;
		}
		if (!Overlay.active() || Overlay.hostMode() || Overlay.hostBusy() || map == null || !haveState
				|| (mode == Mode.DRIVE_HOST && !ready(mc, map))) {
			releaseHostCamera();
			fov = mc.options.fov().get();
			driving = false;
			return;
		}
		driving = mode == Mode.DRIVE_HOST;

		if (mode == Mode.FOLLOW_HOST) {
			releaseHostCamera();
			if (!STATE.has(Protocol.STATE_CAMERA_VALID)) {
				fov = mc.options.fov().get();
				return;
			}
			Vec3 pos = map.toMc(STATE.camPos[0], STATE.camPos[1], STATE.camPos[2]);
			Vec3 dir = map.dirToMc(STATE.camTarget[0] - STATE.camPos[0], STATE.camTarget[1] - STATE.camPos[1],
				STATE.camTarget[2] - STATE.camPos[2]).normalize();
			float yaw = (float) Math.toDegrees(Math.atan2(-dir.x, dir.z));
			float pitch = (float) Math.toDegrees(-Math.asin(Math.max(-1.0, Math.min(1.0, dir.y))));
			CameraAccess access = (CameraAccess) camera;
			access.palcraft$setRotation(yaw, pitch);
			access.palcraft$setPosition(pos);
			fov = STATE.fovYDeg > 1.0F ? STATE.fovYDeg : mc.options.fov().get();
			return;
		}

		// DRIVE_HOST: send our camera to the host game.
		fov = mc.options.fov().get();
		Vec3 p = camera.getPosition();
		Vector3f f = camera.getLookVector();
		Vector3f u = camera.getUpVector();
		double[] pos = map.toHost(p.x, p.y, p.z);
		double[] target = map.toHost(p.x + f.x(), p.y + f.y(), p.z + f.z());
		double[] up = map.dirToHost(u.x(), u.y(), u.z());
		boolean passthrough = FramePassthrough.wanted();
		CONTROL.flags = Protocol.CTRL_OVERRIDE_CAMERA
			| (standIn && mc.player != null ? Protocol.CTRL_MOVE_HUNTER | Protocol.CTRL_HIDE_HUNTER : 0)
			| (passthrough ? Protocol.CTRL_COMPOSITE : 0) | (noDepthTest ? Protocol.CTRL_NO_DEPTH_TEST : 0)
			| (debugDepth ? Protocol.CTRL_DEBUG_DEPTH : 0);
		if (mc.player != null && mc.player.onGround() && !mc.player.getAbilities().flying)
			CONTROL.flags |= Protocol.CTRL_GROUNDED;
		if (mc.player != null && mc.player.getAbilities().flying) CONTROL.flags |= Protocol.CTRL_FLYING;
		CONTROL.poseLag = poseLag;
		CONTROL.depthIndex = depthIndex;
		CONTROL.mcFrame++;
		for (int i = 0; i < 3; i++) {
			CONTROL.camPos[i] = (float) pos[i];
			CONTROL.camTarget[i] = (float) target[i];
			CONTROL.camUp[i] = (float) up[i];
		}
		CONTROL.fovYDeg = fov;
		if (mc.player != null) {
			float pt = camera.getPartialTickTime();
			MovingPlatformClient.copyControl(CONTROL, pt);
			double[] feet = map.toHost(net.minecraft.util.Mth.lerp(pt, mc.player.xo, mc.player.getX()),
				net.minecraft.util.Mth.lerp(pt, mc.player.yo, mc.player.getY()),
				net.minecraft.util.Mth.lerp(pt, mc.player.zo, mc.player.getZ()));
			for (int i = 0; i < 3; i++) {
				CONTROL.hunterPos[i] = (float) feet[i];
			}
			CONTROL.hunterYawDeg = mc.player.getViewYRot(pt);
		}
		controlling = true;
		if (!passthrough) {
			ErLink.get().writeControl(CONTROL);
		}
		// With passthrough, FramePassthrough sends this pose once the frame's pixels are ready.
	}

	/**
	 * Palworld mode: render from Palworld's own camera with Steve standing where its character does, and hand
	 * that same pose back so Palworld shows it together with these pixels.
	 */
	private static void followHostBody(Minecraft mc, CoordMap.Mapping map, Camera camera) {
		Vec3 pos = map.toMc(STATE.camPos[0], STATE.camPos[1], STATE.camPos[2]);
		Vec3 dir = map.dirToMc(STATE.camTarget[0] - STATE.camPos[0], STATE.camTarget[1] - STATE.camPos[1],
			STATE.camTarget[2] - STATE.camPos[2]).normalize();
		float yaw = (float) Math.toDegrees(Math.atan2(-dir.x, dir.z));
		float pitch = (float) Math.toDegrees(-Math.asin(Math.max(-1.0, Math.min(1.0, dir.y))));
		HostBody.place(mc, map, STATE, Math.max(-40.0F, Math.min(40.0F, pitch * 0.6F)));
		CameraAccess access = (CameraAccess) camera;
		access.palcraft$setRotation(yaw, pitch);
		access.palcraft$setPosition(pos);
		access.palcraft$setDetached(true);
		fov = STATE.fovYDeg > 1.0F ? STATE.fovYDeg : mc.options.fov().get();
		driving = true;
		boolean passthrough = FramePassthrough.wanted();
		CONTROL.flags = Protocol.CTRL_OVERRIDE_CAMERA | Protocol.CTRL_HIDE_HUNTER | Protocol.CTRL_HOST_BODY
			| (passthrough ? Protocol.CTRL_COMPOSITE : 0) | (noDepthTest ? Protocol.CTRL_NO_DEPTH_TEST : 0)
			| (debugDepth ? Protocol.CTRL_DEBUG_DEPTH : 0);
		CONTROL.poseLag = poseLag;
		CONTROL.depthIndex = depthIndex;
		CONTROL.mcFrame++;
		for (int i = 0; i < 3; i++) {
			CONTROL.camPos[i] = STATE.camPos[i];
			CONTROL.camTarget[i] = STATE.camTarget[i];
			CONTROL.camUp[i] = i == 1 ? 1.0F : 0.0F;
			CONTROL.hunterPos[i] = STATE.playerPos[i];
		}
		CONTROL.fovYDeg = fov;
		controlling = true;
		if (!passthrough) {
			ErLink.get().writeControl(CONTROL);
		}
	}

	/** Release control even when a pause screen prevents Camera.setup from running. */
	public static void suspend() {
		driving = false;
		releaseHostCamera();
	}

	private static void releaseHostCamera() {
		if (controlling) {
			CONTROL.flags = 0;
			CONTROL.mcFrame++;
			ErLink.get().writeControl(CONTROL);
			controlling = false;
		}
	}
}
