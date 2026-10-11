package dev.palcraft.bridge.client.mixin;

import dev.palcraft.bridge.client.HostBody;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.world.entity.player.Player;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/** In Palworld mode Steve crouches and swims when the Palworld character does. */
@Mixin(Player.class)
public abstract class PlayerMixin {
	@Inject(method = "updatePlayerPose", at = @At("HEAD"), cancellable = true)
	private void palcraft$hostPose(CallbackInfo ci) {
		if ((Object) this instanceof LocalPlayer player && HostBody.active()) {
			player.setPose(HostBody.pose());
			ci.cancel();
		}
	}
}
