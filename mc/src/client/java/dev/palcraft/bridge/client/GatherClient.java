package dev.palcraft.bridge.client;

import dev.palcraft.bridge.ErBridgeMod;
import dev.palcraft.bridge.Gather;
import net.fabricmc.fabric.api.client.networking.v1.ClientPlayNetworking;
import net.minecraft.client.Minecraft;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.core.BlockPos;
import net.minecraft.network.chat.Component;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.phys.BlockHitResult;
import net.minecraft.world.phys.HitResult;

/**
 * Client half of system "gather": times a dig while attack is held on Palworld's world, shows its progress
 * and tells the server when it is done. Palworld's ground has no Minecraft texture to crack, so the progress
 * is a bar above the hotbar, a swinging arm and the sound of hitting stone.
 */
public final class GatherClient {
	private GatherClient() {
	}

	private static final int BAR = 12;
	private static BlockPos target;
	private static int progress, rest;

	public static void tick(Minecraft mc) {
		LocalPlayer player = mc.player;
		if (rest > 0) {
			rest--;
		}
		if (player == null || mc.level == null || mc.screen != null || !mc.options.keyAttack.isDown()
				|| player.isSpectator() || player.getAbilities().instabuild
				|| !(mc.hitResult instanceof BlockHitResult hit) || hit.getType() != HitResult.Type.BLOCK
				|| !ErBridgeMod.isTerrain(mc.level.getBlockState(hit.getBlockPos()))) {
			target = null;
			progress = 0;
			return;
		}
		if (!hit.getBlockPos().equals(target)) {
			target = hit.getBlockPos().immutable();
			progress = 0;
		}
		if (rest > 0) {
			return;
		}
		int need = Gather.digTicks(player.getMainHandItem());
		if (progress % 5 == 0) {
			player.swing(InteractionHand.MAIN_HAND);
			mc.level.playLocalSound(target, SoundEvents.STONE_HIT, SoundSource.BLOCKS, 0.5F, 0.8F, false);
		}
		progress++;
		int filled = Math.min(BAR, progress * BAR / need);
		mc.gui.setOverlayMessage(Component.literal("§a" + "■".repeat(filled) + "§8" + "■".repeat(BAR - filled)), false);
		if (progress >= need) {
			ClientPlayNetworking.send(new Gather.DigPayload(target));
			progress = 0;
			rest = 6;
		}
	}
}
