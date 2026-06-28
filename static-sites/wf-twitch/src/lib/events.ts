export const DISPLAY_TZ = "Asia/Krasnoyarsk";

export type DropEventType = "official" | "creator" | "raid" | "directory";

export type DropEvent = {
  id: string;
  type: DropEventType;
  title: string;
  reward?: string;
  channel: string;
  channelUrl: string;
  start: string;
  end: string;
  watchMinutes?: number;
  sourceUrl: string;
  sourceTitle: string;
};

export type EventsDataset = {
  updatedAt: string;
  timezone: string;
  source: string;
  events: DropEvent[];
};

const TYPE_LABELS: Record<DropEventType, string> = {
  official: "DE / Prime",
  creator: "Creator",
  raid: "Raid",
  directory: "Directory",
};

export function typeLabel(type: DropEventType): string {
  return TYPE_LABELS[type];
}

export function formatRange(startIso: string, endIso: string, tz = DISPLAY_TZ): string {
  const start = new Date(startIso);
  const end = new Date(endIso);
  const dateFmt = new Intl.DateTimeFormat("ru-RU", {
    timeZone: tz,
    day: "numeric",
    month: "short",
  });
  const timeFmt = new Intl.DateTimeFormat("ru-RU", {
    timeZone: tz,
    hour: "2-digit",
    minute: "2-digit",
  });
  const sameDay = dateFmt.format(start) === dateFmt.format(end);
  if (sameDay) {
    return `${dateFmt.format(start)}, ${timeFmt.format(start)}–${timeFmt.format(end)}`;
  }
  return `${dateFmt.format(start)} ${timeFmt.format(start)} – ${dateFmt.format(end)} ${timeFmt.format(end)}`;
}

export function formatRelativeToNow(iso: string, now = Date.now()): string {
  const diff = new Date(iso).getTime() - now;
  const abs = Math.abs(diff);
  const min = Math.round(abs / 60_000);
  if (min < 60) return diff >= 0 ? `через ${min} мин` : `${min} мин назад`;
  const hours = Math.round(min / 60);
  if (hours < 48) return diff >= 0 ? `через ${hours} ч` : `${hours} ч назад`;
  const days = Math.round(hours / 24);
  return diff >= 0 ? `через ${days} д` : `${days} д назад`;
}

export function isLive(event: DropEvent, now = Date.now()): boolean {
  const t = now;
  return t >= new Date(event.start).getTime() && t <= new Date(event.end).getTime();
}

export function isUpcoming(event: DropEvent, now = Date.now()): boolean {
  return new Date(event.start).getTime() > now;
}

export function isPast(event: DropEvent, now = Date.now()): boolean {
  return new Date(event.end).getTime() < now;
}

export type EventGroup = "live" | "today" | "week" | "later" | "past";

export function groupEvent(event: DropEvent, now = Date.now()): EventGroup {
  if (isLive(event, now)) return "live";
  if (isPast(event, now)) return "past";

  const tz = DISPLAY_TZ;
  const start = new Date(event.start);
  const todayParts = new Intl.DateTimeFormat("en-CA", {
    timeZone: tz,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date(now));
  const startParts = new Intl.DateTimeFormat("en-CA", {
    timeZone: tz,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(start);

  if (startParts === todayParts) return "today";

  const weekAhead = now + 7 * 24 * 60 * 60_000;
  if (start.getTime() <= weekAhead) return "week";
  return "later";
}

export const GROUP_TITLES: Record<EventGroup, string> = {
  live: "Сейчас в эфире",
  today: "Сегодня",
  week: "На этой неделе",
  later: "Позже",
  past: "Недавно прошло",
};
