package dev.palcraft.bridge.client.mixin;

import dev.palcraft.bridge.client.HostBody;
import dev.palcraft.bridge.gen.Tune;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.client.renderer.LightTexture;
import net.minecraft.client.renderer.culling.Frustum;
import net.minecraft.client.renderer.entity.EntityRenderer;
import net.minecraft.world.entity.Entity;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

/**
 * System "steve_body": Palworld lights its own night; Minecraft's would leave Steve a black shape in it.
 * And a camera that a wall has pushed against Steve's back shows the world, not the back.
 */
@Mixin(EntityRenderer.class)
public abstract class EntityRendererMixin {
	@Inject(method = "shouldRender", at = @At("HEAD"), cancellable = true)
	private void palcraft$bodyTooClose(Entity entity, Frustum frustum, double x, double y, double z,
			CallbackInfoReturnable<Boolean> cir) {
		if (entity instanceof LocalPlayer && HostBody.tooClose()) {
			cir.setReturnValue(false);
		}
	}

	@Inject(method = "getPackedLightCoords", at = @At("RETURN"), cancellable = true)
	private void palcraft$bodyLight(Entity entity, float partialTicks, CallbackInfoReturnable<Integer> cir) {
		if (entity instanceof LocalPlayer && HostBody.active()) {
			int packed = cir.getReturnValue();
			int block = Math.max(LightTexture.block(packed), (int) Tune.BODY_MIN_LIGHT);
			cir.setReturnValue(LightTexture.pack(block, LightTexture.sky(packed)));
		}
	}
}
