import { useCallback, useEffect, useMemo, useState } from "react";
import { IconExternalLink, IconRefresh, IconVideo } from "@tabler/icons-react";
import { siteEdgeUrl } from "@shared/site-urls";
import { BellReminderSwitch } from "@/components/bell-reminder-switch";
import { WarframeBreadcrumb } from "@/components/warframe-breadcrumb";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import {
  DISPLAY_TZ,
  GROUP_TITLES,
  type DropEvent,
  type EventGroup,
  formatRange,
  formatRelativeToNow,
  groupEvent,
  isLive,
  isPast,
  typeLabel,
} from "@/lib/events";
import {
  checkReminders,
  currentNotificationPermission,
  loadEventsDataset,
  loadNotifyEnabled,
  loadReminders,
  notificationsSupported,
  notificationsAllowedHere,
  requestNotificationPermission,
  saveNotifyEnabled,
  sendTestNotification,
  setReminder,
  subscribeToEvents,
  unsubscribeFromAllEvents,
} from "@/lib/notifications";
import { cn } from "@/lib/utils";

const GROUP_ORDER: EventGroup[] = ["live", "today", "week", "later", "past"];

function typeBadgeVariant(type: DropEvent["type"]): "default" | "secondary" | "outline" {
  if (type === "directory") return "default";
  if (type === "official") return "secondary";
  return "outline";
}

function EventCard({
  event,
  now,
  onReminderChange,
  reminderOn,
  remindersDisabled,
}: {
  event: DropEvent;
  now: number;
  onReminderChange: (id: string, enabled: boolean) => void;
  reminderOn: boolean;
  remindersDisabled: boolean;
}) {
  const live = isLive(event, now);

  return (
    <Card
      className={cn(
        "transition",
        live && "ring-2 ring-purple-500/40",
        reminderOn && "border-purple-500/35 bg-purple-500/[0.04]",
        event.type === "directory" && !reminderOn && "border-purple-500/20",
      )}
    >
      <CardHeader className="gap-2">
        <div className="flex flex-wrap items-start justify-between gap-2">
          <div className="space-y-1">
            <div className="flex flex-wrap items-center gap-2">
              <CardTitle className="text-base">{event.title}</CardTitle>
              {live && (
                <Badge className="border-purple-500/30 bg-purple-500/15 text-purple-200">LIVE</Badge>
              )}
              {reminderOn && (
                <Badge className="border-purple-500/40 bg-purple-500/20 text-purple-100">Напомню</Badge>
              )}
            </div>
            <CardDescription>{formatRange(event.start, event.end)} · Красноярск</CardDescription>
          </div>
          <div className="flex flex-wrap items-center gap-2 sm:justify-end">
            <Badge variant={typeBadgeVariant(event.type)}>{typeLabel(event.type)}</Badge>
            <BellReminderSwitch
              checked={reminderOn}
              compact
              disabled={remindersDisabled}
              label={`Напомнить: ${event.title}`}
              onCheckedChange={(enabled) => onReminderChange(event.id, enabled)}
            />
          </div>
        </div>
      </CardHeader>
      <CardContent className="space-y-3">
        {event.reward && <p className="text-sm text-foreground/90">{event.reward}</p>}
        <div className="flex flex-wrap gap-2 text-xs text-muted-foreground">
          {event.watchMinutes && <span>Смотреть: {event.watchMinutes} мин</span>}
          <span>{formatRelativeToNow(event.start, now)}</span>
          {event.channel !== "directory" && <span>Канал: {event.channel}</span>}
        </div>
        <div className="flex flex-wrap gap-2">
          <Button asChild size="sm">
            <a href={event.channelUrl} rel="noopener noreferrer" target="_blank">
              <IconVideo className="size-4" />
              Открыть стрим
            </a>
          </Button>
          <Button asChild size="sm" variant="ghost">
            <a href={event.sourceUrl} rel="noopener noreferrer" target="_blank">
              <IconExternalLink className="size-4" />
              Источник
            </a>
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}

export default function App() {
  const [dataset, setDataset] = useState<Awaited<ReturnType<typeof loadEventsDataset>> | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [now, setNow] = useState(() => Date.now());
  const [notifyEnabled, setNotifyEnabled] = useState(loadNotifyEnabled);
  const [notifyPermission, setNotifyPermission] = useState<NotificationPermission>(
    notificationsSupported() ? Notification.permission : "denied",
  );
  const [reminderIds, setReminderIds] = useState(() => new Set(Object.keys(loadReminders())));

  const refreshReminders = useCallback(() => {
    setReminderIds(new Set(Object.keys(loadReminders())));
  }, []);

  const refresh = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await loadEventsDataset();
      setDataset(data);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Не удалось загрузить расписание");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  useEffect(() => {
    const tick = window.setInterval(() => setNow(Date.now()), 30_000);
    return () => window.clearInterval(tick);
  }, []);

  useEffect(() => {
    const sync = () => setNotifyPermission(currentNotificationPermission());
    document.addEventListener("visibilitychange", sync);
    window.addEventListener("focus", sync);
    return () => {
      document.removeEventListener("visibilitychange", sync);
      window.removeEventListener("focus", sync);
    };
  }, []);

  useEffect(() => {
    if (!dataset?.events.length) return;
    checkReminders(dataset.events, now);
    const id = window.setInterval(() => {
      setNow(Date.now());
      checkReminders(dataset.events, Date.now());
    }, 60_000);
    return () => window.clearInterval(id);
  }, [dataset, now]);

  const grouped = useMemo(() => {
    const map = new Map<EventGroup, DropEvent[]>();
    for (const key of GROUP_ORDER) map.set(key, []);
    for (const event of dataset?.events ?? []) {
      const group = groupEvent(event, now);
      map.get(group)?.push(event);
    }
    return map;
  }, [dataset, now]);

  const upcomingEvents = useMemo(
    () => (dataset?.events ?? []).filter((event) => !isPast(event, now)),
    [dataset, now],
  );

  const upcomingIds = useMemo(() => upcomingEvents.map((event) => event.id), [upcomingEvents]);

  const subscribedUpcomingCount = useMemo(
    () => upcomingIds.filter((id) => reminderIds.has(id)).length,
    [upcomingIds, reminderIds],
  );

  const allUpcomingSubscribed =
    upcomingIds.length > 0 && upcomingIds.every((id) => reminderIds.has(id));

  const remindersDisabled = !notificationsAllowedHere();

  async function ensureNotificationsEnabled(): Promise<boolean> {
    if (!notificationsAllowedHere()) return false;
    if (Notification.permission === "granted") {
      if (!notifyEnabled) {
        setNotifyEnabled(true);
        saveNotifyEnabled(true);
      }
      return true;
    }
    const perm = await requestNotificationPermission();
    setNotifyPermission(perm);
    if (perm !== "granted") return false;
    setNotifyEnabled(true);
    saveNotifyEnabled(true);
    sendTestNotification();
    return true;
  }

  async function handleNotifyToggle(enabled: boolean) {
    if (!notificationsSupported()) return;
    if (enabled) {
      const ok = await ensureNotificationsEnabled();
      if (!ok) return;
      return;
    }
    setNotifyEnabled(false);
    saveNotifyEnabled(false);
  }

  function handleRecheckPermission() {
    const perm = currentNotificationPermission();
    setNotifyPermission(perm);
    if (perm === "granted") {
      setNotifyEnabled(true);
      saveNotifyEnabled(true);
      sendTestNotification();
    }
  }

  async function handleReminderChange(eventId: string, enabled: boolean) {
    if (enabled) {
      const ok = await ensureNotificationsEnabled();
      if (!ok) return;
    }
    setReminder(eventId, enabled);
    refreshReminders();
  }

  async function handleSubscribeAll() {
    if (upcomingIds.length === 0) return;
    if (allUpcomingSubscribed) {
      unsubscribeFromAllEvents();
      refreshReminders();
      return;
    }
    const ok = await ensureNotificationsEnabled();
    if (!ok) return;
    subscribeToEvents(upcomingIds);
    refreshReminders();
  }

  const siteHost = typeof window !== "undefined" ? window.location.hostname : "wftwitch.home";
  const secureContext = typeof window !== "undefined" && window.isSecureContext;
  const httpsUrl = siteEdgeUrl("wfTwitch");

  const updatedLabel = dataset
    ? new Intl.DateTimeFormat("ru-RU", {
        timeZone: DISPLAY_TZ,
        dateStyle: "medium",
        timeStyle: "short",
      }).format(new Date(dataset.updatedAt))
    : null;

  return (
    <main className="mx-auto min-h-screen w-full max-w-3xl px-4 py-8 sm:px-6 sm:py-10">
      <WarframeBreadcrumb current="Twitch Drops" />

      <header className="mb-8">
        <div className="mb-3 flex flex-wrap items-center gap-2">
          <Badge variant="outline" className="border-purple-500/30 text-purple-300">
            Twitch Drops
          </Badge>
          <Badge variant="outline">Красноярск (UTC+7)</Badge>
        </div>
        <h1 className="text-2xl font-bold tracking-tight sm:text-3xl">WF Twitch Drops</h1>
        <p className="mt-2 text-sm text-muted-foreground sm:text-base">
          Расписание дропов из официального RSS форума Warframe Livestreams. Напоминания — в браузере
          (нужна открытая вкладка).
        </p>
      </header>

      <div className="mb-4 flex flex-wrap items-center gap-2">
        <Button disabled={loading} size="sm" variant="outline" onClick={() => void refresh()}>
          <IconRefresh className={cn("size-4", loading && "animate-spin")} />
          Обновить
        </Button>
        {updatedLabel && (
          <span className="text-xs text-muted-foreground">Данные: {updatedLabel}</span>
        )}
      </div>

      {notificationsAllowedHere() && (
        <Card
          className={cn(
            "mb-6 transition",
            notifyEnabled
              ? "border-purple-500/40 bg-purple-500/[0.07] ring-1 ring-purple-500/15"
              : "border-border/80",
          )}
        >
          <CardContent className="flex flex-col gap-4 pt-4">
            <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
              <div className="space-y-1">
                <p className="text-sm font-medium">Напоминания в браузере</p>
                <p className="text-xs text-muted-foreground">
                  За 15, 5 и 0 мин до старта · подписок: {subscribedUpcomingCount} из {upcomingIds.length}
                </p>
              </div>
              <BellReminderSwitch
                checked={notifyEnabled}
                label="Напоминания в браузере"
                onCheckedChange={(enabled) => void handleNotifyToggle(enabled)}
              />
            </div>
            <div className="flex justify-end border-t border-border/60 pt-3">
              <Button
                disabled={upcomingIds.length === 0}
                size="sm"
                variant={allUpcomingSubscribed ? "secondary" : "outline"}
                className={cn(
                  allUpcomingSubscribed && "border-purple-500/30 bg-purple-500/15 text-purple-100",
                )}
                onClick={() => void handleSubscribeAll()}
              >
                {allUpcomingSubscribed ? "Снять все подписки" : "Подписаться на всё"}
              </Button>
            </div>
          </CardContent>
        </Card>
      )}

      {!secureContext && notificationsSupported() && (
        <Card className="mb-4 border-purple-500/30 bg-purple-500/5">
          <CardHeader className="pb-2">
            <CardTitle className="text-base">Уведомления только по HTTPS</CardTitle>
            <CardDescription>
              Сейчас сайт открыт как <code className="text-foreground">http://{siteHost}</code>. Chrome и Edge
              не дают включить push на незащищённом HTTP — пункт «Уведомления» в настройках будет серым.
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-3 text-sm">
            <p>Открой HTTPS-версию (тот же сайт, другой адрес):</p>
            <Button asChild size="sm">
              <a href={httpsUrl}>{httpsUrl}</a>
            </Button>
            <p className="text-xs text-muted-foreground">
              После перехода включи свитч напоминаний и разреши уведомления в браузере.
            </p>
          </CardContent>
        </Card>
      )}

      {secureContext && notifyPermission === "denied" && notificationsSupported() && (
        <Card className="mb-4 border-amber-500/30 bg-amber-500/5">
          <CardHeader className="pb-2">
            <CardTitle className="text-base text-amber-100">Уведомления заблокированы</CardTitle>
            <CardDescription className="text-amber-100/80">
              Браузер не даст спросить снова — нужно разрешить вручную для{" "}
              <span className="font-medium text-foreground">{siteHost}</span>.
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-3 text-sm text-amber-50/90">
            <p className="font-medium text-foreground">Chrome / Edge</p>
            <ol className="list-decimal space-y-1 pl-5">
              <li>
                Слева от адреса нажми значок <strong>«Настройки сайта»</strong> (замок или слайдеры).
              </li>
              <li>
                <strong>Разрешения</strong> → <strong>Уведомления</strong> → <strong>Разрешить</strong>.
              </li>
              <li>Вернись на вкладку и нажми «Проверить снова».</li>
            </ol>
            <Button size="sm" variant="secondary" onClick={handleRecheckPermission}>
              Проверить снова
            </Button>
          </CardContent>
        </Card>
      )}

      {error && (
        <Card className="mb-6 border-destructive/40">
          <CardContent className="pt-4 text-sm text-destructive">{error}</CardContent>
        </Card>
      )}

      {loading && !dataset && <p className="text-sm text-muted-foreground">Загрузка расписания…</p>}

      {!loading && dataset && dataset.events.length === 0 && (
        <Card>
          <CardContent className="pt-4 text-sm text-muted-foreground">
            Ближайших ивентов нет. Запусти <code className="text-foreground">npm run sync-events</code>{" "}
            перед деплоем или проверь RSS форума.
          </CardContent>
        </Card>
      )}

      <div className="space-y-8">
        {GROUP_ORDER.map((group) => {
          const events = grouped.get(group) ?? [];
          if (!events.length) return null;
          return (
            <section key={group}>
              <h2 className="mb-3 text-sm font-semibold tracking-wide text-muted-foreground uppercase">
                {GROUP_TITLES[group]}
              </h2>
              <div className="space-y-3">
                {events.map((event) => (
                  <EventCard
                    key={event.id}
                    event={event}
                    now={now}
                    reminderOn={reminderIds.has(event.id)}
                    remindersDisabled={remindersDisabled}
                    onReminderChange={(id, enabled) => void handleReminderChange(id, enabled)}
                  />
                ))}
              </div>
            </section>
          );
        })}
      </div>

      <p className="mt-10 text-xs text-muted-foreground">
        Аккаунты Warframe и Twitch должны быть связаны на{" "}
        <a className="text-primary hover:underline" href="https://www.warframe.com/user" rel="noreferrer" target="_blank">
          warframe.com/user
        </a>
        .
      </p>
    </main>
  );
}
