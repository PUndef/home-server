import type { DropRow, DropsDataset, FarmSource } from "@/lib/parse-drops";
import { normalizeItemKey } from "@/lib/parse-drops";
import { estimateMinutes, speedTierForType, speedTierLabel, type SpeedTier } from "@/lib/mission-speed";

export type FarmMatch = {
  source: FarmSource;
  drop: DropRow;
  minutes: number;
  speedTier: SpeedTier;
  expectedPerRun: number;
  efficiency: number;
};

export type SearchOptions = {
  missionsOnly?: boolean;
  hideEvents?: boolean;
  hideConclave?: boolean;
};

function matchesQuery(itemKey: string, query: string): boolean {
  const q = normalizeItemKey(query);
  if (!q) return false;
  if (itemKey === q) return true;
  if (itemKey.includes(q)) return true;
  const qTokens = q.split(/\s+/).filter(Boolean);
  return qTokens.every((token) => itemKey.includes(token));
}

function effectiveChance(drop: DropRow): number {
  const base = drop.chance.percent / 100;
  if (drop.resourceModifier != null && drop.resourceModifier > 0) {
    return base * (drop.resourceModifier / 100);
  }
  return base;
}

export function rankMatches(dataset: DropsDataset, query: string, options: SearchOptions = {}): FarmMatch[] {
  const matches: FarmMatch[] = [];

  for (const source of dataset.sources) {
    if (options.missionsOnly && !source.isMission) continue;
    if (options.hideEvents && source.isEvent) continue;
    if (options.hideConclave && source.missionType?.includes("Conclave")) continue;

    for (const drop of source.drops) {
      if (!matchesQuery(drop.itemKey, query)) continue;

      const minutes = estimateMinutes(source.missionType ?? undefined, drop.rotation);
      const expected = effectiveChance(drop) * drop.quantity;
      const efficiency = expected / Math.max(minutes, 0.5);

      matches.push({
        source,
        drop,
        minutes,
        speedTier: speedTierForType(source.missionType ?? undefined),
        expectedPerRun: expected,
        efficiency,
      });
    }
  }

  matches.sort((a, b) => {
    if (b.efficiency !== a.efficiency) return b.efficiency - a.efficiency;
    return b.drop.chance.percent - a.drop.chance.percent;
  });

  return matches;
}

export function formatEfficiency(value: number): string {
  return value < 0.01 ? value.toExponential(2) : value.toFixed(3);
}

export { speedTierLabel };
