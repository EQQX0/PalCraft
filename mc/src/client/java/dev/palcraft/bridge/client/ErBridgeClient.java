package dev.palcraft.bridge.client;

import com.mojang.blaze3d.platform.InputConstants;
import dev.palcraft.bridge.CoordMap;
import dev.palcraft.bridge.link.GameState;
import dev.palcraft.bridge.link.ErLink;
import dev.palcraft.bridge.link.Protocol;
import net.fabricmc.api.ClientModInitializer;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;
import net.fabricmc.fabric.api.client.keybinding.v1.KeyBindingHelper;
import net.fabricmc.fabric.api.client.rendering.v1.EntityRendererRegistry;
import net.fabricmc.fabric.api.client.rendering.v1.HudRenderCallback;
import dev.palcraft.bridge.entity.ErBridgeEntities;
import net.minecraft.client.KeyMapping;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.network.chat.Component;
import org.lwjgl.glfw.GLFW;

public class ErBridgeClient implements ClientModInitializer {
	private static final GameState HUD_STATE = new GameState();
	private static KeyMapping cameraModeKey;
	private static KeyMapping overlayKey;
	private static KeyMapping hudKey;
	private static KeyMapping hunterKey;
	private static KeyMapping passthroughKey;
	private static KeyMapping actionKey;
	/** Last Palworld action request still waiting for its result (0 = none). */
	private static int pendingAction;
	private static long pendingActionSince;
	private static boolean showStatus = false;

	@Override
	public void onInitializeClient() {
		cameraModeKey = KeyBindingHelper.registerKeyBinding(new KeyMapping("key.palcraft.camera_mode",
			InputConstants.Type.KEYSYM, GLFW.GLFW_KEY_F7, "category.palcraft"));
		overlayKey = KeyBindingHelper.registerKeyBinding(new KeyMapping("key.palcraft.overlay",
			InputConstants.Type.KEYSYM, GLFW.GLFW_KEY_F8, "category.palcraft"));
		hudKey = KeyBindingHelper.registerKeyBinding(new KeyMapping("key.palcraft.status",
			InputConstants.Type.KEYSYM, GLFW.GLFW_KEY_F9, "category.palcraft"));
		hunterKey = KeyBindingHelper.registerKeyBinding(new KeyMapping("key.palcraft.hunter",
			InputConstants.Type.KEYSYM, GLFW.GLFW_KEY_F10, "category.palcraft"));
		// E is Minecraft's inventory, so Palworld's "action" (open doors, pull levers, pick up
		// items and lost runes, talks) gets its own key.
		actionKey = KeyBindingHelper.registerKeyBinding(new KeyMapping("key.palcraft.action",
			InputConstants.Type.KEYSYM, GLFW.GLFW_KEY_R, "category.palcraft"));
		passthroughKey = KeyBindingHelper.registerKeyBinding(new KeyMapping("key.palcraft.passthrough",
			InputConstants.Type.KEYSYM, GLFW.GLFW_KEY_F6, "category.palcraft"));

		ClientTickEvents.START_CLIENT_TICK.register(MovingPlatformClient::tick);
		ClientTickEvents.END_CLIENT_TICK.register(mc -> {
			while (cameraModeKey.consumeClick()) {
				CameraSync.toggleMode();
				toast(mc, "Camera: " + CameraSync.mode());
			}
			while (overlayKey.consumeClick()) {
				// Hand control to the host game (menus, quest board, travelling...). F8 there comes back.
				Overlay.switchToHost(mc);
			}
			while (hudKey.consumeClick()) {
				// Debug view: bridge status line, hitbox outlines, every HP tag.
				showStatus = !showStatus;
				ErEntityRenderer.showHitboxes = showStatus;
				toast(mc, "Debug view " + (showStatus ? "on" : "off"));
			}
			while (passthroughKey.consumeClick()) {
				FramePassthrough.toggle();
				toast(mc, "Draw inside Palworld (occlusion): " + (FramePassthrough.enabled() ? "on" : "off"));
			}
			while (actionKey.consumeClick()) {
				if (Overlay.active() && !Overlay.hostBusy() && ErLink.get().alive()) {
					pendingAction = ErLink.get().requestAction();
					pendingActionSince = System.currentTimeMillis();
				}
			}
			if (pendingAction != 0) {
				ErLink link = ErLink.get();
				if (link.actionAck() == pendingAction) {
					int r = link.actionResult();
					if (r == 0) {
						toast(mc, "Nothing to do here in Palworld");
					} else if (r == -2) {
						toast(mc, "Ladders need Palworld's controls: press F8, climb, F8 back");
					} else if (r < 0) {
						toast(mc, "Palworld actions aren't available in this game version");
					} else if (mc.player != null) {
						// A door or gate may be moving: Minecraft's copy of the ground there goes stale.
						dev.palcraft.bridge.TerrainManager.resampleAround(mc.player.getX(), mc.player.getZ(), 4);
					}
					pendingAction = 0;
				} else if (System.currentTimeMillis() - pendingActionSince > 2000) {
					pendingAction = 0;
				}
			}
			while (hunterKey.consumeClick()) {
				toast(mc, CameraSync.toggleStandIn()
					? "Palworld character stands in for you (enemies can hit you)" : "Palworld character stays put and visible");
			}
			WorldBootstrap.tick(mc);
			DevCommands.tick(mc);
		});

		HudRenderCallback.EVENT.register((graphics, tickCounter) -> {
			renderPrompt(graphics);
			renderStatus(graphics);
		});
		EntityRendererRegistry.register(ErBridgeEntities.ER_ENTITY, ErEntityRenderer::new);
	}

	private static void toast(Minecraft mc, String msg) {
		if (mc.player != null) {
			mc.player.displayClientMessage(Component.literal("[ER Bridge] " + msg), true);
		}
	}

	/** Palworld's current action ("Open", "Pick up"...) under the crosshair, with the key to press. */
	private static void renderPrompt(GuiGraphics g) {
		Minecraft mc = Minecraft.getInstance();
		if (mc.options.hideGui || !Overlay.active() || Overlay.hostBusy() || mc.screen != null) {
			return;
		}
		String prompt = ErLink.get().hostPrompt();
		if (prompt.isEmpty()) {
			return;
		}
		String text = "[" + actionKey.getTranslatedKeyMessage().getString() + "] " + prompt;
		int w = mc.font.width(text);
		int x = (g.guiWidth() - w) / 2;
		int y = g.guiHeight() / 2 + 14;
		g.fill(x - 3, y - 2, x + w + 3, y + 10, 0x80000000);
		g.drawString(mc.font, text, x, y, 0xFFE8D8A0, true);
	}

	private static void renderStatus(GuiGraphics g) {
		Minecraft mc = Minecraft.getInstance();
		if (!showStatus || mc.options.hideGui || mc.getDebugOverlay().showDebugScreen()) {
			return;
		}
		ErLink link = ErLink.get();
		String line1;
		String line2 = null;
		if (!link.alive()) {
			line1 = "Palworld: not connected";
		} else {
			boolean have = link.snapshot(HUD_STATE);
			line1 = String.format("Palworld: live  frame %d  %s  camera %s%s", have ? HUD_STATE.frame : 0,
				!Overlay.active() ? "overlay off" : FramePassthrough.activeInHost() ? "drawn inside Palworld" : "overlay window", CameraSync.mode(),
				CameraSync.mode() == CameraSync.Mode.DRIVE_HOST && !CameraSync.hostFollowing() ? " (Palworld not following yet)" : "");
			if (have && HUD_STATE.has(Protocol.STATE_PLAYER_VALID)) {
				line2 = String.format("tarnished %.0f %.0f %.0f", HUD_STATE.playerPos[0], HUD_STATE.playerPos[1], HUD_STATE.playerPos[2]);
			} else if (CoordMap.get() != null && CoordMap.get().provisional()) {
				line2 = "Palworld character position unknown (provisional anchor)";
			}
		}
		g.drawString(mc.font, line1, 4, 4, 0xFFFFFF, true);
		if (line2 != null) {
			g.drawString(mc.font, line2, 4, 14, 0xFFFFFF, true);
		}
	}
}
