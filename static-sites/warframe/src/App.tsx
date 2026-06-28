import { IconArrowRight, IconBrandTwitch, IconSearch, IconSwords } from "@tabler/icons-react";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { siteUrl } from "@shared/site-urls";
import { cn } from "@/lib/utils";

const apps = [
  {
    id: "requiem" as const,
    title: "Requiem Helper",
    description: "Подбор requiem-модов для murmur по результатам попыток Mercy.",
    badge: "Kuva Lich",
    icon: IconSwords,
    accent: "border-violet-500/30 hover:ring-violet-500/20",
  },
  {
    id: "wfFarm" as const,
    title: "WF Farm Helper",
    description: "Поиск выгодных миссий под фарм ресурса, релика или мода по PC Drops.",
    badge: "Drops",
    icon: IconSearch,
    accent: "border-amber-500/30 hover:ring-amber-500/20",
  },
  {
    id: "wfTwitch" as const,
    title: "WF Twitch Drops",
    description: "Расписание Twitch-дропов, напоминания и ссылки на стримы — по часовому поясу Красноярска.",
    badge: "Twitch",
    icon: IconBrandTwitch,
    accent: "border-purple-500/30 hover:ring-purple-500/20",
  },
] as const;

export default function App() {
  return (
    <main className="mx-auto flex min-h-screen w-full max-w-4xl flex-col px-4 py-10 sm:px-6 sm:py-16">
      <header className="mb-10 text-center">
        <Badge variant="outline" className="mb-3 border-primary/30 text-primary">
          Warframe Tools
        </Badge>
        <h1 className="text-3xl font-bold tracking-tight sm:text-4xl">Warframe Tools</h1>
        <p className="mx-auto mt-3 max-w-xl text-base text-muted-foreground">
          Помощники для Warframe — выбирай инструмент ниже.
        </p>
      </header>

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {apps.map((app) => (
          <a
            key={app.id}
            className="group block rounded-lg outline-none focus-visible:ring-2 focus-visible:ring-ring/50"
            href={siteUrl(app.id)}
          >
            <Card
              className={cn(
                "h-full transition hover:bg-muted/40 hover:ring-2",
                app.accent,
              )}
            >
              <CardHeader>
                <div className="flex items-start justify-between gap-3">
                  <div className="flex size-10 items-center justify-center rounded-md border bg-input/30 text-primary">
                    <app.icon className="size-5" />
                  </div>
                  <Badge variant="outline">{app.badge}</Badge>
                </div>
                <CardTitle className="text-lg">{app.title}</CardTitle>
                <CardDescription>{app.description}</CardDescription>
              </CardHeader>
              <CardContent>
                <span className="inline-flex items-center gap-1 text-sm font-medium text-primary transition group-hover:gap-2">
                  Открыть
                  <IconArrowRight className="size-4" />
                </span>
              </CardContent>
            </Card>
          </a>
        ))}
      </div>
    </main>
  );
}
