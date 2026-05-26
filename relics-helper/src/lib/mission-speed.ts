import { ROTATION_MINUTES } from "@/lib/constants";

/** Baseline minutes to complete one reward roll for a mission type (solo, casual speedrun). */
const BASE_MINUTES: Record<string, number> = {
  Capture: 2,
  Rescue: 2.5,
  Exterminate: 4,
  Sabotage: 4,
  Spy: 5,
  "Mobile Defense": 5,
  Defection: 6,
  Disruption: 5,
  Interception: 5,
  Excavation: 6,
  Survival: 5,
  Defense: 5,
  Assassination: 5,
  Caches: 7,
  "Dark Sector Defense": 10,
  "Dark Sector Survival": 10,
  "Dark Sector Excavation": 8,
  "Dark Sector Interception": 6,
  "Dark Sector Defection": 8,
  "Dark Sector Sabotage": 5,
  "Dark Sector Spy": 5,
  Skirmish: 12,
  "Skirmish Extra": 12,
  Pursuit: 10,
  Rush: 8,
  Hijack: 6,
  "Hive Sabotage": 8,
  "Hive Defense": 10,
  "Hive Survival": 10,
  "Void Cascade": 12,
  "Void Flood": 10,
  "Void Armageddon": 12,
  "Alchemy Endless": 15,
  "Shrine Defense": 12,
  Conclave: 8,
};

const SLOW_TYPES = new Set([
  "Survival",
  "Defense",
  "Excavation",
  "Defection",
  "Skirmish",
  "Pursuit",
  "Alchemy Endless",
  "Shrine Defense",
]);

const FAST_TYPES = new Set(["Capture", "Rescue", "Exterminate", "Sabotage", "Spy"]);

export type SpeedTier = "fast" | "medium" | "slow" | "other";

export function speedTierForType(missionType?: string): SpeedTier {
  if (!missionType) return "other";
  const base = missionType.replace(/\s+Extra$/, "");
  if (FAST_TYPES.has(base)) return "fast";
  if (SLOW_TYPES.has(base) || base.startsWith("Dark Sector")) return "slow";
  if (BASE_MINUTES[base] !== undefined) return "medium";
  return "other";
}

export function speedTierLabel(tier: SpeedTier): string {
  if (tier === "fast") return "быстро";
  if (tier === "medium") return "средне";
  if (tier === "slow") return "долго";
  return "прочее";
}

export function estimateMinutes(missionType?: string, rotation?: string | null): number {
  if (!missionType) return 10;
  const baseType = missionType.replace(/\s+Extra$/, "");
  const base = BASE_MINUTES[baseType] ?? 8;
  if (rotation && ROTATION_MINUTES[rotation] !== undefined) {
    return ROTATION_MINUTES[rotation];
  }
  if (SLOW_TYPES.has(baseType)) return base + 10;
  return base;
}
