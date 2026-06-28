import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createHash } from "node:crypto";

const RSS_URL = "https://forums.warframe.com/forum/113-livestreams.xml/";
const DEFAULT_TZ = "Asia/Krasnoyarsk";
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const out = path.join(root, "public", "events.json");

const MONTHS = {
  january: 0,
  february: 1,
  march: 2,
  april: 3,
  may: 4,
  june: 5,
  july: 6,
  august: 7,
  september: 8,
  october: 9,
  november: 10,
  december: 11,
};

const DOW = {
  sunday: 0,
  monday: 1,
  tuesday: 2,
  wednesday: 3,
  thursday: 4,
  friday: 5,
  saturday: 6,
};

function htmlToText(html) {
  return html
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/(p|li|div|h\d|ul)>/gi, "\n")
    .replace(/<[^>]+>/g, "")
    .replace(/&amp;/g, "&")
    .replace(/&nbsp;/g, " ")
    .replace(/&#\d+;/g, "")
    .replace(/\r/g, "")
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)
    .join("\n");
}

function parseTimeToken(raw) {
  const m = raw
    .trim()
    .toLowerCase()
    .replace(/\./g, "")
    .match(/^(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$/);
  if (!m) return null;
  let hour = Number(m[1]);
  const minute = Number(m[2] ?? 0);
  const meridiem = m[3];
  if (meridiem === "pm" && hour < 12) hour += 12;
  if (meridiem === "am" && hour === 12) hour = 0;
  if (!meridiem && hour <= 7) hour += 12;
  return { hour, minute };
}

function etToUtcIso(year, monthIndex, day, hour, minute) {
  let ms = Date.UTC(year, monthIndex, day, hour, minute);
  for (let i = 0; i < 4; i++) {
    const parts = new Intl.DateTimeFormat("en-US", {
      timeZone: "America/New_York",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      hour12: false,
    }).formatToParts(new Date(ms));
    const get = (type) => Number(parts.find((p) => p.type === type)?.value);
    const nyHour = get("hour");
    const nyMinute = get("minute");
    const nyDay = get("day");
    const diffMin = (hour - nyHour) * 60 + (minute - nyMinute) + (day - nyDay) * 24 * 60;
    if (diffMin === 0) break;
    ms += diffMin * 60_000;
  }
  return new Date(ms).toISOString();
}

function parseMonthDay(text, yearFallback) {
  const m = text.match(/(\w+)\s+(\d{1,2})(?:st|nd|rd|th)?(?:\s+(\d{4}))?/i);
  if (!m) return null;
  const month = MONTHS[m[1].toLowerCase()];
  if (month === undefined) return null;
  const day = Number(m[2]);
  const year = m[3] ? Number(m[3]) : yearFallback;
  return { year, month, day };
}

function dayInWeekRange(dayName, monthName, startDay, endDay, year) {
  const month = MONTHS[monthName.toLowerCase()];
  const target = DOW[dayName.toLowerCase()];
  if (month === undefined || target === undefined) return startDay;
  for (let d = startDay; d <= endDay; d++) {
    if (new Date(year, month, d).getDay() === target) return d;
  }
  return startDay;
}

function parseWeekRange(title) {
  const m = title.match(
    /(\w+)\s+(\d{1,2})(?:st|nd|rd|th)?\s*-\s*(\d{1,2})(?:st|nd|rd|th)?\s+(\d{4})/i,
  );
  if (!m) return null;
  const monthName = m[1];
  const month = MONTHS[monthName.toLowerCase()];
  if (month === undefined) return null;
  return {
    monthName,
    month,
    startDay: Number(m[2]),
    endDay: Number(m[3]),
    year: Number(m[4]),
  };
}

function eventId(parts) {
  return createHash("sha1").update(parts.join("|")).digest("hex").slice(0, 12);
}

function normalizeChannel(raw) {
  return raw.replace(/^@/, "").trim();
}

function addEvent(bucket, event) {
  bucket.push(event);
}

function parseRssItems(xml) {
  const items = [];
  const re = /<item>([\s\S]*?)<\/item>/g;
  let match;
  while ((match = re.exec(xml))) {
    const block = match[1];
    const title = block.match(/<title>(?:<!\[CDATA\[)?([\s\S]*?)(?:\]\]>)?<\/title>/)?.[1]?.trim();
    const link = block.match(/<link>([\s\S]*?)<\/link>/)?.[1]?.trim();
    const desc = block.match(/<description>(?:<!\[CDATA\[)?([\s\S]*?)(?:\]\]>)?<\/description>/)?.[1];
    if (title && link && desc) items.push({ title, link, description: desc });
  }
  return items;
}

function parseOfficialStreams(text, ctx) {
  const events = [];
  const week = parseWeekRange(ctx.title);
  const year = week?.year ?? new Date().getFullYear();

  const primeRe =
    /twitch\.tv\/([\w_]+)[\s\S]*?on\s+(?:(\w+day),\s+)?(\w+)\s+(\d{1,2})(?:st|nd|rd|th)?[\s\S]*?(?:begins at|at)\s+(\d{1,2}(?::\d{2})?\s*(?:p\.?m\.?|a\.?m\.?))/gi;
  let m;
  while ((m = primeRe.exec(text))) {
    const channel = normalizeChannel(m[1]);
    const monthName = m[3];
    const month = MONTHS[monthName.toLowerCase()];
    const day = Number(m[4]);
    const time = parseTimeToken(m[5].replace(/\s+/g, ""));
    if (month === undefined || !time) continue;
    const start = etToUtcIso(year, month, day, time.hour, time.minute);
    const label = /Pride Time/i.test(text.slice(m.index, m.index + 500))
      ? "Pride Time"
      : /Prime Time/i.test(text.slice(m.index, m.index + 500))
        ? "Prime Time"
        : "Official stream";
    addEvent(events, {
      id: eventId([channel, start, label]),
      type: "official",
      title: label,
      reward: extractRewardNear(text, m.index),
      channel,
      channelUrl: `https://www.twitch.tv/${channel}`,
      start,
      end: new Date(new Date(start).getTime() + 2 * 60 * 60_000).toISOString(),
      watchMinutes: extractWatchMinutes(text, m.index) ?? 30,
      sourceUrl: ctx.link,
      sourceTitle: ctx.title,
    });
  }

  const emisionRe =
    /Emisi[oó]n Tenno on (\w+)\s+(\d{1,2})(?:st|nd|rd|th)? at (\d{1,2}(?::\d{2})?\s*(?:p\.?m\.?|a\.?m\.?))[\s\S]*?twitch\.tv\/([\w_]+)/gi;
  while ((m = emisionRe.exec(text))) {
    const monthName = m[1];
    const month = MONTHS[monthName.toLowerCase()];
    const day = Number(m[2]);
    const time = parseTimeToken(m[3].replace(/\s+/g, ""));
    const channel = normalizeChannel(m[4]);
    if (month === undefined || !time) continue;
    const start = etToUtcIso(year, month, day, time.hour, time.minute);
    addEvent(events, {
      id: eventId([channel, start, "Emisión Tenno"]),
      type: "official",
      title: "Emisión Tenno",
      reward: extractRewardNear(text, m.index),
      channel,
      channelUrl: `https://www.twitch.tv/${channel}`,
      start,
      end: new Date(new Date(start).getTime() + 2 * 60 * 60_000).toISOString(),
      watchMinutes: extractWatchMinutes(text, m.index) ?? 30,
      sourceUrl: ctx.link,
      sourceTitle: ctx.title,
    });
  }

  return events;
}

function extractWatchMinutes(text, index) {
  const slice = text.slice(index, index + 400);
  const m = slice.match(/(\d+)\s+minutes?/i);
  return m ? Number(m[1]) : null;
}

function extractRewardNear(text, index) {
  const slice = text.slice(index, index + 800);
  const dropLine = slice.match(/Drop:\s*(.+)/i);
  if (dropLine) return dropLine[1].trim();
  const bullet = slice.match(/\*\s*(.+Talents.+)\*/i) ?? slice.match(/(\d+x .+ per \d+ minutes)/i);
  return bullet?.[1]?.trim();
}

function parseCreatorBlocks(text, ctx) {
  const events = [];
  const week = parseWeekRange(ctx.title);
  const year = week?.year ?? new Date().getFullYear();
  const lines = text.split("\n");

  for (let i = 0; i < lines.length; i++) {
    const nameLine = lines[i].match(/^(.+?)\s*\([^)]+\)\s*$/);
    if (!nameLine) continue;
    const creator = nameLine[1].trim();
    const dateLine = lines[i + 1] ?? "";
    const channelLine = lines[i + 2] ?? "";
    const dropLine = lines[i + 3] ?? "";

    const range = dateLine.match(
      /(\w+)\s+(\d{1,2})(?:st|nd|rd|th)?\s+from\s+(\d{1,2}(?::\d{2})?(?:pm|am)?)\s+to\s+(\d{1,2}(?::\d{2})?(?:pm|am)?)\s+ET/i,
    );
    const channelMatch =
      channelLine.match(/twitch\.tv\/([\w_]+)/i) ?? dateLine.match(/twitch\.tv\/([\w_]+)/i);
    const dropMatch = dropLine.match(/^Drop:\s*(.+)$/i) ?? channelLine.match(/^Drop:\s*(.+)$/i);

    if (!range || !channelMatch) continue;

    const month = MONTHS[range[1].toLowerCase()];
    const day = Number(range[2]);
    const startTime = parseTimeToken(range[3]);
    const endTime = parseTimeToken(range[4]);
    if (month === undefined || !startTime || !endTime) continue;

    const channel = normalizeChannel(channelMatch[1]);
    const start = etToUtcIso(year, month, day, startTime.hour, startTime.minute);
    const end = etToUtcIso(year, month, day, endTime.hour, endTime.minute);

    addEvent(events, {
      id: eventId([channel, start, creator]),
      type: "creator",
      title: creator,
      reward: dropMatch?.[1]?.trim(),
      channel,
      channelUrl: `https://www.twitch.tv/${channel}`,
      start,
      end,
      watchMinutes: 30,
      sourceUrl: ctx.link,
      sourceTitle: ctx.title,
    });
  }

  return events;
}

function parseRaids(text, ctx) {
  const events = [];
  const week = parseWeekRange(ctx.title);
  if (!week) return events;

  const re =
    /Watch\s+([\w_]+)\s+for\s+(\d+)\s+minutes?\s+on\s+(\w+day)(?:\s+from\s+(\d{1,2}(?::\d{2})?(?:pm|am)?)\s+to\s+(\d{1,2}(?::\d{2})?(?:pm|am)?))?\s+ET/gi;
  let m;
  while ((m = re.exec(text))) {
    const channel = normalizeChannel(m[1]);
    const watchMinutes = Number(m[2]);
    const dayName = m[3];
    const day = dayInWeekRange(dayName, week.monthName, week.startDay, week.endDay, week.year);
    const startTime = m[4] ? parseTimeToken(m[4]) : { hour: 12, minute: 0 };
    const endTime = m[5] ? parseTimeToken(m[5]) : { hour: startTime.hour + 1, minute: startTime.minute };
    if (!startTime || !endTime) continue;

    const start = etToUtcIso(week.year, week.month, day, startTime.hour, startTime.minute);
    const end = etToUtcIso(week.year, week.month, day, endTime.hour, endTime.minute);

    addEvent(events, {
      id: eventId([channel, start, "raid"]),
      type: "raid",
      title: `Raid: ${channel}`,
      reward: "Unity Decoration",
      channel,
      channelUrl: `https://www.twitch.tv/${channel}`,
      start,
      end,
      watchMinutes,
      sourceUrl: ctx.link,
      sourceTitle: ctx.title,
    });
  }

  return events;
}

function parseDirectoryCampaign(text, ctx) {
  const events = [];
  const rangeRe =
    /From\s+(\w+)\s+(\d{1,2})(?:st|nd|rd|th)?\s+at\s+(\d{1,2}(?::\d{2})?(?:PM|AM|pm|am)?)\s+ET\s+to\s+(\w+)\s+(\d{1,2})(?:st|nd|rd|th)?\s+at\s+(\d{1,2}(?::\d{2})?(?:PM|AM|pm|am)?)\s+ET/i;
  const m = text.match(rangeRe);
  if (!m) return events;

  const startMonth = MONTHS[m[1].toLowerCase()];
  const endMonth = MONTHS[m[4].toLowerCase()];
  const startTime = parseTimeToken(m[3]);
  const endTime = parseTimeToken(m[6]);
  const year = new Date().getFullYear();
  if (startMonth === undefined || endMonth === undefined || !startTime || !endTime) return events;

  const start = etToUtcIso(year, startMonth, Number(m[2]), startTime.hour, startTime.minute);
  const end = etToUtcIso(year, endMonth, Number(m[5]), endTime.hour, endTime.minute);

  const rewards = [...text.matchAll(/\*\s*(.+?):\s*(.+)/g)]
    .filter((r) => /hour|minute/i.test(r[1]))
    .map((r) => `${r[1].trim()}: ${r[2].trim()}`);

  const titleMatch = ctx.title.match(/^(.+?)\s+Directory-Wide/i);
  const title = titleMatch?.[1]?.trim() ?? "Directory-wide drops";

  addEvent(events, {
    id: eventId([title, start]),
    type: "directory",
    title,
    reward: rewards.length ? rewards.join(" · ") : "Cumulative watch rewards",
    channel: "directory",
    channelUrl: "https://www.twitch.tv/directory/category/warframe",
    start,
    end,
    watchMinutes: 60,
    sourceUrl: ctx.link,
    sourceTitle: ctx.title,
  });

  return events;
}

function dedupeEvents(events) {
  const map = new Map();
  for (const e of events) map.set(e.id, e);
  return [...map.values()].sort((a, b) => a.start.localeCompare(b.start));
}

function filterUpcoming(events, keepPastDays = 2) {
  const cutoff = Date.now() - keepPastDays * 24 * 60 * 60_000;
  return events.filter((e) => new Date(e.end).getTime() >= cutoff);
}

async function main() {
  const response = await fetch(RSS_URL);
  if (!response.ok) throw new Error(`RSS HTTP ${response.status}`);
  const xml = await response.text();
  const items = parseRssItems(xml);

  const all = [];
  const scheduleItems = items.filter((i) => /Community Stream Schedule/i.test(i.title));
  const directoryItems = items.filter((i) => /Directory-Wide Twitch Drops/i.test(i.title));

  for (const item of scheduleItems.slice(0, 3)) {
    const text = htmlToText(item.description);
    all.push(...parseOfficialStreams(text, item));
    all.push(...parseCreatorBlocks(text, item));
    all.push(...parseRaids(text, item));
    all.push(...parseDirectoryCampaign(text, item));
  }

  for (const item of directoryItems.slice(0, 2)) {
    const text = htmlToText(item.description);
    all.push(...parseDirectoryCampaign(text, item));
  }

  const events = filterUpcoming(dedupeEvents(all));
  const dataset = {
    updatedAt: new Date().toISOString(),
    timezone: DEFAULT_TZ,
    source: RSS_URL,
    events,
  };

  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, `${JSON.stringify(dataset, null, 2)}\n`);
  console.log(`Wrote ${events.length} events -> ${out}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
