package dev.palcraft.bridge.client.mixin;

import com.mojang.blaze3d.vertex.PoseStack;
import dev.palcraft.bridge.client.HostBody;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.client.renderer.MultiBufferSource;
import net.minecraft.client.renderer.entity.layers.ItemInHandLayer;
import net.minecraft.world.entity.LivingEntity;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/**
 * System "steve_body": in Palworld mode Palworld's tools do the work, so Steve's hands are empty: the Minecraft
 * item in his hotbar is not what he swings there.
 */
@Mixin(ItemInHandLayer.class)
public abstract class ItemInHandLayerMixin {
	@Inject(method = "render(Lcom/mojang/blaze3d/vertex/PoseStack;Lnet/minecraft/client/renderer/MultiBufferSource;"
			+ "ILnet/minecraft/world/entity/LivingEntity;FFFFFF)V", at = @At("HEAD"), cancellable = true)
	private void palcraft$emptyHands(PoseStack poseStack, MultiBufferSource buffer, int packedLight, LivingEntity entity,
			float limbSwing, float limbSwingAmount, float partialTicks, float ageInTicks, float netHeadYaw,
			float headPitch, CallbackInfo ci) {
		if (entity instanceof LocalPlayer && HostBody.active()) {
			ci.cancel();
		}
	}
}
