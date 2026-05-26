export type ParsedChance = {
  rarity: string;
  percent: number;
};

export type DropRow = {
  item: string;
  itemKey: string;
  quantity: number;
  chance: ParsedChance;
  rotation: string | null;
  resourceModifier: number | null;
};

export type FarmSource = {
  section: string;
  label: string;
  planet: string | null;
  node: string | null;
  missionType: string | null;
  isMission: boolean;
  isEvent: boolean;
  drops: DropRow[];
};

export type DropsDataset = {
  lastUpdate: string | null;
  sources: FarmSource[];
  itemIndex: Map<string, FarmSource[]>;
};

const CHANCE_RE = /^(.+?)\s*\((\d+(?:\.\d+)?)%\)$/;
const ROTATION_RE = /^Rotation\s+([ABC])$/i;
const MISSION_RE = /^(?:Event:\s*)?([^/]+)\/(.+?)\s+\(([^)]+)\)(?:\s+(Extra))?$/;
const QUANTITY_RE = /^(\d+)X\s+/i;

const MISSION_SECTIONS = new Set([
  "Missions",
  "Dynamic Location Rewards",
  "Sorties",
  "Cetus Bounty Rewards",
  "Orb Vallis Bounty Rewards",
  "Cambion Drift Bounty Rewards",
  "Zariman Bounty Rewards",
  "Albrecht's Laboratories Bounty Rewards",
  "Hex Bounty Rewards",
]);

const REVERSE_SECTIONS = new Set([
  "Resource Drops by Resource",
  "Blueprint/Item Drops by Blueprint/Item",
  "Mod Drops by Mod",
]);

export function normalizeItemKey(item: string): string {
  return item
    .replace(QUANTITY_RE, "")
    .replace(/,/g, "")
    .toLowerCase()
    .trim();
}

export function parseQuantity(item: string): number {
  const match = item.match(QUANTITY_RE);
  return match ? Number(match[1]) : 1;
}

function parseChanceCell(text: string): ParsedChance | null {
  const match = text.trim().match(CHANCE_RE);
  if (!match) return null;
  return { rarity: match[1].trim(), percent: Number(match[2]) };
}

function parseMissionHeader(text: string) {
  const match = text.trim().match(MISSION_RE);
  if (!match) return null;
  const [, planet, node, missionType, extra] = match;
  return {
    planet: planet.trim(),
    node: node.trim(),
    missionType: extra ? `${missionType.trim()} Extra` : missionType.trim(),
    isEvent: text.trim().startsWith("Event:"),
  };
}

function isBlankRow(row: HTMLTableRowElement): boolean {
  return row.classList.contains("blank-row");
}

function cellText(el: Element | null | undefined): string {
  return el?.textContent?.trim() ?? "";
}

function pushDrop(
  source: FarmSource,
  item: string,
  chanceText: string,
  rotation: string | null,
  resourceModifier: number | null,
) {
  const chance = parseChanceCell(chanceText);
  if (!chance) return;
  source.drops.push({
    item,
    itemKey: normalizeItemKey(item),
    quantity: parseQuantity(item),
    chance,
    rotation,
    resourceModifier,
  });
}

function parseMissionTable(table: HTMLTableElement, section: string): FarmSource[] {
  const sources: FarmSource[] = [];
  let current: FarmSource | null = null;
  let rotation: string | null = null;

  for (const row of Array.from(table.rows)) {
    if (isBlankRow(row)) {
      current = null;
      rotation = null;
      continue;
    }

    const header = row.querySelector("th[colspan='2']");
    if (header) {
      const text = cellText(header);
      const rot = text.match(ROTATION_RE);
      if (rot) {
        rotation = rot[1].toUpperCase();
        continue;
      }
      const mission = parseMissionHeader(text);
      if (mission) {
        current = {
          section,
          label: text,
          planet: mission.planet,
          node: mission.node,
          missionType: mission.missionType,
          isMission: true,
          isEvent: mission.isEvent,
          drops: [],
        };
        sources.push(current);
        rotation = null;
      } else {
        current = {
          section,
          label: text,
          planet: null,
          node: null,
          missionType: null,
          isMission: MISSION_SECTIONS.has(section),
          isEvent: false,
          drops: [],
        };
        sources.push(current);
        rotation = null;
      }
      continue;
    }

    const cells = row.cells;
    if (!current || cells.length < 2) continue;
    const item = cellText(cells[0]);
    const chanceText = cellText(cells[1]);
    if (!item) continue;
    pushDrop(current, item, chanceText, rotation, null);
  }

  return sources;
}

function parseReverseIndexTable(table: HTMLTableElement, section: string): FarmSource[] {
  const sources: FarmSource[] = [];
  let itemName: string | null = null;
  let pendingSource: FarmSource | null = null;

  for (const row of Array.from(table.rows)) {
    if (isBlankRow(row)) {
      itemName = null;
      pendingSource = null;
      continue;
    }

    const resourceHeader = row.querySelector("th[colspan='3']");
    if (resourceHeader) {
      itemName = cellText(resourceHeader);
      pendingSource = null;
      continue;
    }

    const cells = row.cells;
    if (cells.length === 3 && cellText(cells[0]) === "Source") continue;

    if (itemName && cells.length >= 3) {
      const sourceLabel = cellText(cells[0]);
      const modifierText = cellText(cells[1]).replace("%", "");
      const chanceText = cellText(cells[2]);
      if (!sourceLabel) continue;

      pendingSource = {
        section,
        label: sourceLabel,
        planet: null,
        node: null,
        missionType: null,
        isMission: false,
        isEvent: false,
        drops: [],
      };
      sources.push(pendingSource);
      const modifier = Number(modifierText);
      pushDrop(
        pendingSource,
        itemName,
        chanceText,
        null,
        Number.isFinite(modifier) ? modifier : null,
      );
    }
  }

  return sources;
}

function extractLastUpdate(doc: Document): string | null {
  const bodyText = doc.body?.textContent ?? "";
  const match = bodyText.match(/Last Update:\s*([^\n<]+)/i);
  return match ? match[1].trim() : null;
}

export function parseDropsHtml(html: string): DropsDataset {
  const doc = new DOMParser().parseFromString(html, "text/html");
  const sources: FarmSource[] = [];
  const headings = Array.from(doc.querySelectorAll("h3[id]"));

  for (const heading of headings) {
    const section = heading.textContent?.replace(/:$/, "").trim() ?? "Unknown";
    const table = heading.nextElementSibling;
    if (!(table instanceof HTMLTableElement)) continue;

    if (REVERSE_SECTIONS.has(section)) {
      sources.push(...parseReverseIndexTable(table, section));
    } else if (MISSION_SECTIONS.has(section) || section === "Relics" || section === "Keys") {
      sources.push(...parseMissionTable(table, section));
    } else if (section.endsWith("by Source") || section.endsWith("by Drop")) {
      sources.push(...parseMissionTable(table, section));
    }
  }

  const itemIndex = new Map<string, FarmSource[]>();
  for (const source of sources) {
    for (const drop of source.drops) {
      const list = itemIndex.get(drop.itemKey) ?? [];
      if (!list.includes(source)) list.push(source);
      itemIndex.set(drop.itemKey, list);
    }
  }

  return {
    lastUpdate: extractLastUpdate(doc),
    sources,
    itemIndex,
  };
}
