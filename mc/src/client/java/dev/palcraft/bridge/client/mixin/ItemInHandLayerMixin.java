package dev.palcraft.bridge.client.mixin;

import dev.palcraft.bridge.client.HostBody;
import dev.palcraft.bridge.client.LoadoutHud;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.client.renderer.entity.layers.ItemInHandLayer;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.item.ItemStack;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Redirect;

/**
 * System "loadout_hotbar": in Palworld mode Palworld's tools do the work, so Steve holds the Minecraft item that
 * stands for the one in hand there, and nothing in his other hand. His own items wait in his inventory.
 */
@Mixin(ItemInHandLayer.class)
public abstract class ItemInHandLayerMixin {
	private static final String RENDER = "render(Lcom/mojang/blaze3d/vertex/PoseStack;"
		+ "Lnet/minecraft/client/renderer/MultiBufferSource;ILnet/minecraft/world/entity/LivingEntity;FFFFFF)V";

	@Redirect(method = RENDER, at = @At(value = "INVOKE",
		target = "Lnet/minecraft/world/entity/LivingEntity;getMainHandItem()Lnet/minecraft/world/item/ItemStack;"))
	private ItemStack palcraft$palworldTool(LivingEntity entity) {
		return entity instanceof LocalPlayer && HostBody.active() ? LoadoutHud.inHand() : entity.getMainHandItem();
	}

	@Redirect(method = RENDER, at = @At(value = "INVOKE",
		target = "Lnet/minecraft/world/entity/LivingEntity;getOffhandItem()Lnet/minecraft/world/item/ItemStack;"))
	private ItemStack palcraft$emptyOtherHand(LivingEntity entity) {
		return entity instanceof LocalPlayer && HostBody.active() ? ItemStack.EMPTY : entity.getOffhandItem();
	}
}
