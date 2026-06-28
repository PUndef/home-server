import type { DropEvent, EventsDataset } from "@/lib/events";

const REMINDERS_KEY = "wf-twitch-reminders-v1";
const FIRED_KEY = "wf-twitch-reminders-fired-v1";
const NOTIFY_KEY = "wf-twitch-notify-enabled-v1";
const DEFAULT_MINUTES = [15, 5, 0];

export function notificationsSupported(): boolean {
  return typeof Notification !== "undefined";
}

/** Chrome/Edge allow Notification API only on HTTPS (or localhost). */
export function notificationsAllowedHere(): boolean {
  return notificationsSupported() && window.isSecureContext;
}

export function loadNotifyEnabled(): boolean {
  try {
    return localStorage.getItem(NOTIFY_KEY) === "1";
  } catch {
    return false;
  }
}

export function saveNotifyEnabled(enabled: boolean) {
  localStorage.setItem(NOTIFY_KEY, enabled ? "1" : "0");
}

export function loadReminders(): Record<string, number[]> {
  try {
    const raw = localStorage.getItem(REMINDERS_KEY);
    if (!raw) return {};
    return JSON.parse(raw) as Record<string, number[]>;
  } catch {
    return {};
  }
}

export function saveReminders(reminders: Record<string, number[]>) {
  localStorage.setItem(REMINDERS_KEY, JSON.stringify(reminders));
}

export function toggleReminder(eventId: string): boolean {
  return setReminder(eventId, !loadReminders()[eventId]);
}

export function setReminder(eventId: string, enabled: boolean): boolean {
  const reminders = loadReminders();
  if (enabled) {
    reminders[eventId] = DEFAULT_MINUTES;
    saveReminders(reminders);
    return true;
  }
  if (reminders[eventId]) {
    delete reminders[eventId];
    saveReminders(reminders);
  }
  return false;
}

export function subscribeToEvents(eventIds: string[]) {
  const reminders = loadReminders();
  for (const id of eventIds) reminders[id] = DEFAULT_MINUTES;
  saveReminders(reminders);
}

export function unsubscribeFromAllEvents() {
  saveReminders({});
}

export function isReminderOn(eventId: string): boolean {
  return Boolean(loadReminders()[eventId]);
}

function loadFired(): Record<string, number[]> {
  try {
    const raw = localStorage.getItem(FIRED_KEY);
    if (!raw) return {};
    return JSON.parse(raw) as Record<string, number[]>;
  } catch {
    return {};
  }
}

function saveFired(fired: Record<string, number[]>) {
  localStorage.setItem(FIRED_KEY, JSON.stringify(fired));
}

export function currentNotificationPermission(): NotificationPermission {
  if (!notificationsSupported()) return "denied";
  return Notification.permission;
}

export async function requestNotificationPermission(): Promise<NotificationPermission> {
  if (!notificationsSupported()) return "denied";
  if (Notification.permission === "granted") return "granted";
  if (Notification.permission === "denied") return "denied";
  return Notification.requestPermission();
}

export function sendTestNotification() {
  if (!notificationsSupported() || Notification.permission !== "granted") return false;
  const n = new Notification("WF Twitch Drops", {
    body: "Уведомления работают. Не закрывай вкладку перед ивентом.",
    tag: "wf-twitch-test",
  });
  n.onclick = () => {
    window.focus();
    n.close();
  };
  return true;
}

function fireNotification(event: DropEvent, minutesBefore: number) {
  const when =
    minutesBefore === 0
      ? "начинается сейчас"
      : `через ${minutesBefore} мин (${new Date(event.start).toLocaleTimeString("ru-RU", { timeZone: "Asia/Krasnoyarsk", hour: "2-digit", minute: "2-digit" })})`;
  const body = [event.reward, when, event.channel !== "directory" ? event.channel : "Warframe directory"]
    .filter(Boolean)
    .join(" · ");

  const n = new Notification(`WF Drop: ${event.title}`, {
    body,
    tag: `${event.id}-${minutesBefore}`,
  });
  n.onclick = () => {
    window.open(event.channelUrl, "_blank", "noopener,noreferrer");
    window.focus();
    n.close();
  };
}

export function checkReminders(events: DropEvent[], now = Date.now()) {
  if (!notificationsSupported()) return;
  if (Notification.permission !== "granted") return;
  if (!loadNotifyEnabled()) return;

  const reminders = loadReminders();
  const fired = loadFired();
  let changed = false;

  for (const event of events) {
    const minutesList = reminders[event.id];
    if (!minutesList?.length) continue;

    const startMs = new Date(event.start).getTime();
    const firedForEvent = fired[event.id] ?? [];

    for (const minutesBefore of minutesList) {
      if (firedForEvent.includes(minutesBefore)) continue;
      const triggerAt = startMs - minutesBefore * 60_000;
      if (now >= triggerAt && now < startMs + 5 * 60_000) {
        fireNotification(event, minutesBefore);
        firedForEvent.push(minutesBefore);
        changed = true;
      }
    }

    if (firedForEvent.length) fired[event.id] = firedForEvent;
  }

  if (changed) saveFired(fired);
}

export async function loadEventsDataset(): Promise<EventsDataset> {
  const url = `${import.meta.env.BASE_URL}events.json`;
  const response = await fetch(url, { cache: "no-cache" });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response.json() as Promise<EventsDataset>;
}
