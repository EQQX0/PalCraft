package dev.palcraft.bridge.mixin;

import dev.palcraft.bridge.NativeTerrainCollision;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.phys.Vec3;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.ModifyVariable;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;
import net.minecraft.world.entity.MoverType;

@Mixin(Entity.class)
public abstract class EntityCollisionMixin {
    @Unique private Vec3 palcraft$traceStart, palcraft$traceRequested, palcraft$traceProjected;
    @ModifyVariable(method = "move", at = @At("HEAD"), argsOnly = true, ordinal = 0)
    private Vec3 palcraft$wallSliding(Vec3 movement) {
        Entity entity = (Entity)(Object)this;
        palcraft$traceStart = NativeTerrainCollision.tracingMovement() ? entity.position() : null;
        palcraft$traceRequested = movement;
        palcraft$traceProjected = NativeTerrainCollision.slide(entity, movement);
        return palcraft$traceProjected;
    }

    @Inject(method = "move", at = @At("RETURN"))
    private void palcraft$finishMove(MoverType type, Vec3 movement, CallbackInfo callback) {
        Entity entity = (Entity)(Object)this;
        try {
            if (palcraft$traceStart != null)
                NativeTerrainCollision.traceMove(entity, palcraft$traceStart, palcraft$traceRequested, palcraft$traceProjected);
        } finally {
            NativeTerrainCollision.finishMove(entity);
            palcraft$traceStart = null;
        }
    }

}
