package dev.palcraft.bridge;

import net.fabricmc.loader.api.entrypoint.PreLaunchEntrypoint;
import org.apache.logging.log4j.Level;
import org.apache.logging.log4j.core.config.Configurator;

/** Minecraft's system-info library (OSHI) warns when a PC lacks the page-file performance counter.
 * The warnings are harmless and read like a failed launch, so only its errors reach the log. */
public final class QuietLog implements PreLaunchEntrypoint {
	@Override
	public void onPreLaunch() {
		Configurator.setLevel("oshi", Level.ERROR);
	}
}
