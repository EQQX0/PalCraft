package dev.palcraft.bridge.client.mixin;

import dev.palcraft.bridge.client.HostBody;
import dev.palcraft.bridge.client.LoadoutHud;
import dev.palcraft.bridge.client.MenuSteve;
import dev.palcraft.bridge.client.Overlay;
import net.minecraft.client.CameraType;
import net.minecraft.client.DeltaTracker;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.Gui;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.world.entity.Entity;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.Redirect;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/**
 * The vignette is drawn with a blend mode that would make the whole window opaque. The crosshair stays up
 * behind Steve: the middle of the picture is where he aims, in Minecraft's third person and in Palworld mode.
 */
@Mixin(Gui.class)
public abstract class GuiMixin {
	@Inject(method = "renderVignette", at = @At("HEAD"), cancellable = true)
	private void palcraft$noVignette(GuiGraphics graphics, Entity entity, CallbackInfo ci) {
		if (Overlay.active()) {
			ci.cancel();
		}
	}

	/** Palworld's inventory screen: Steve where its character preview was, and nothing else of Minecraft's. */
	@Inject(method = "render", at = @At("HEAD"), cancellable = true)
	private void palcraft$steveInPalworldInventory(GuiGraphics graphics, DeltaTracker delta, CallbackInfo ci) {
		if (HostBody.previewing()) {
			MenuSteve.render(Minecraft.getInstance(), graphics);
			ci.cancel();
		}
	}

	/** Palworld mode: the hotbar shows the tools of Palworld's weapon slots, which do the work there. */
	@Inject(method = "renderItemHotbar", at = @At("HEAD"), cancellable = true)
	private void palcraft$palworldLoadout(GuiGraphics graphics, DeltaTracker delta, CallbackInfo ci) {
		if (HostBody.active()) {
			LoadoutHud.render(Minecraft.getInstance(), graphics);
			ci.cancel();
		}
	}

	/** And no name of the Minecraft item Steve is not holding there. */
	@Inject(method = "renderSelectedItemName", at = @At("HEAD"), cancellable = true)
	private void palcraft$noItemNameInPalworldMode(GuiGraphics graphics, CallbackInfo ci) {
		if (HostBody.active()) {
			ci.cancel();
		}
	}

	@Redirect(method = "renderCrosshair", at = @At(value = "INVOKE",
		target = "Lnet/minecraft/client/CameraType;isFirstPerson()Z"))
	private boolean palcraft$crosshairBehindSteve(CameraType type) {
		return type.isFirstPerson() || HostBody.active() || (Overlay.active() && type == CameraType.THIRD_PERSON_BACK);
	}
}
