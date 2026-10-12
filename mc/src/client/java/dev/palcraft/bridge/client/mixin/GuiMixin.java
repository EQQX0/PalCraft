package dev.palcraft.bridge.client.mixin;

import dev.palcraft.bridge.client.HostBody;
import dev.palcraft.bridge.client.Overlay;
import net.minecraft.client.gui.Gui;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.world.entity.Entity;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/**
 * The vignette is drawn with a blend mode that would make the whole window opaque. Palworld mode looks at Steve
 * from behind: no crosshair, as in Minecraft's own third person (Palworld draws its reticle when he aims).
 */
@Mixin(Gui.class)
public abstract class GuiMixin {
	@Inject(method = "renderVignette", at = @At("HEAD"), cancellable = true)
	private void palcraft$noVignette(GuiGraphics graphics, Entity entity, CallbackInfo ci) {
		if (Overlay.active()) {
			ci.cancel();
		}
	}

	@Inject(method = "renderCrosshair", at = @At("HEAD"), cancellable = true)
	private void palcraft$noCrosshairBehindSteve(CallbackInfo ci) {
		if (HostBody.active()) {
			ci.cancel();
		}
	}
}
