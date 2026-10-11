package dev.palcraft.bridge.client.mixin;

import dev.palcraft.bridge.client.HostBody;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.world.entity.LivingEntity;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/** In Palworld mode Steve's walk cycle follows the Palworld character's speed, not Minecraft's own movement. */
@Mixin(LivingEntity.class)
public abstract class LivingEntityMixin {
	@Inject(method = "calculateEntityAnimation", at = @At("HEAD"), cancellable = true)
	private void palcraft$hostWalk(boolean includeHeight, CallbackInfo ci) {
		if ((Object) this instanceof LocalPlayer && HostBody.active()) {
			ci.cancel();
		}
	}
}
