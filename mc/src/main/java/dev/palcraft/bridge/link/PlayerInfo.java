package dev.palcraft.bridge.link;

/** One other player of the Palworld session (PlayerRow). The place is in host metres: convert it with {@code CoordMap}. */
public final class PlayerInfo {
	public long id;
	public int flags;
	/** 0..1. */
	public float health;
	/** Feet. */
	public final float[] pos = new float[3];
	/** Unreal yaw of the body, and where the player looks (up positive). */
	public float yawDeg, pitchDeg;
	public String name = "";
	/** Palworld's class name of the tool in hand; empty = bare hands. */
	public String tool = "";

	public boolean has(int flag) {
		return (flags & flag) != 0;
	}
}
