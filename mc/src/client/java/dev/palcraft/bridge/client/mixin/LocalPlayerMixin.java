package dev.palcraft.bridge.client.mixin;

import dev.palcraft.bridge.client.HostBody;
import net.minecraft.client.player.LocalPlayer;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/** In Palworld mode the server places Steve itself: moves from the client would be checked against terrain and thrown back. */
@Mixin(LocalPlayer.class)
public abstract class LocalPlayerMixin {
	@Inject(method = "sendPosition", at = @At("HEAD"), cancellable = true)
	private void palcraft$noMovesWhileFollowing(CallbackInfo ci) {
		if (HostBody.active()) {
			ci.cancel();
		}
	}
}
