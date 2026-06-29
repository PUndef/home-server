import { useEffect, useState } from "react";
import { IconAlertTriangle, IconCircleCheck, IconRefresh, IconRoute } from "@tabler/icons-react";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { cn } from "@/lib/utils";

type Check = { name: string; status: "ok" | "warn" | "fail"; detail: string };
type RouteInfo = {
  ip: string;
  interface: string;
  status: string;
  raw?: string;
};
type Snapshot = {
  timestamp: string;
  mode: string;
  primary: string;
  login_flag: boolean;
  policies: { name: string; interface: string }[];
  routes: { steam_auth: RouteInfo; steam_cdn: RouteInfo };
  checks: Check[];
  summary: { ok: number; warn: number; fail: number; overall: string };
};

function statusColor(status: string) {
  if (status === "ok") return "text-emerald-400";
  if (status === "warn") return "text-amber-400";
  return "text-red-400";
}

function StatusIcon({ status }: { status: string }) {
  if (status === "ok") return <IconCircleCheck className="size-5 text-emerald-400" />;
  return <IconAlertTriangle className={cn("size-5", statusColor(status))} />;
}

export default function App() {
  const [snapshot, setSnapshot] = useState<Snapshot | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  async function load() {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch("./status.json", { cache: "no-store" });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      setSnapshot((await res.json()) as Snapshot);
    } catch (err) {
      setError(err instanceof Error ? err.message : "load failed");
      setSnapshot(null);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void load();
    const id = window.setInterval(() => void load(), 120_000);
    return () => window.clearInterval(id);
  }, []);

  const overall = snapshot?.summary.overall ?? "unknown";

  return (
    <main className="mx-auto flex min-h-screen w-full max-w-5xl flex-col gap-6 px-4 py-10 sm:px-6">
      <header className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <Badge variant="outline" className="mb-3 border-sky-500/30 text-sky-300">
            pundef-pc routing
          </Badge>
          <h1 className="flex items-center gap-2 text-3xl font-bold tracking-tight">
            <IconRoute className="size-8 text-sky-400" />
            Network Routing
          </h1>
          <p className="mt-2 max-w-2xl text-muted-foreground">
            Автоматический baseline: Steam auth → туннель, CDN → WAN. Обновляется cron на static-sites LXC.
          </p>
        </div>
        <button
          type="button"
          onClick={() => void load()}
          className="inline-flex items-center gap-2 rounded-md border px-3 py-2 text-sm hover:bg-muted/40"
        >
          <IconRefresh className={cn("size-4", loading && "animate-spin")} />
          Обновить
        </button>
      </header>

      <Card className={cn("border-2", overall === "ok" ? "border-emerald-500/30" : "border-red-500/30")}>
        <CardHeader>
          <div className="flex items-center gap-3">
            <StatusIcon status={overall} />
            <div>
              <CardTitle>Общий статус: {overall.toUpperCase()}</CardTitle>
              <CardDescription>
                {snapshot?.timestamp ? `Снимок: ${new Date(snapshot.timestamp).toLocaleString("ru-RU")}` : "—"}
                {snapshot ? ` · primary=${snapshot.primary} · mode=${snapshot.mode}` : ""}
              </CardDescription>
            </div>
          </div>
        </CardHeader>
        {snapshot && (
          <CardContent className="grid gap-4 sm:grid-cols-2">
            <div className="rounded-md border border-emerald-500/20 bg-emerald-500/5 p-4">
              <div className="text-sm font-medium text-emerald-300">Destiny login path</div>
              <div className="mt-1 font-mono text-xs text-muted-foreground">
                {snapshot.routes.steam_auth.ip} → {snapshot.routes.steam_auth.interface}
              </div>
              <div className={cn("mt-2 text-sm", statusColor(snapshot.routes.steam_auth.status))}>
                {snapshot.routes.steam_auth.status === "ok"
                  ? "Cold login OK (auth через туннель)"
                  : "Сломан — centipede risk"}
              </div>
            </div>
            <div className="rounded-md border border-sky-500/20 bg-sky-500/5 p-4">
              <div className="text-sm font-medium text-sky-300">Steam CDN</div>
              <div className="mt-1 font-mono text-xs text-muted-foreground">
                {snapshot.routes.steam_cdn.ip} → {snapshot.routes.steam_cdn.interface}
              </div>
              <div className={cn("mt-2 text-sm", statusColor(snapshot.routes.steam_cdn.status))}>
                {snapshot.routes.steam_cdn.status === "ok" ? "CDN через WAN" : "CDN path broken"}
              </div>
            </div>
          </CardContent>
        )}
      </Card>

      {error && (
        <Card className="border-red-500/30">
          <CardContent className="py-4 text-sm text-red-300">
            Не удалось загрузить status.json: {error}. Cron collector ещё не настроен?
          </CardContent>
        </Card>
      )}

      {snapshot && (
        <>
          <section>
            <h2 className="mb-3 text-lg font-semibold">Проверки</h2>
            <div className="grid gap-2">
              {snapshot.checks.map((check) => (
                <div
                  key={check.name}
                  className="flex items-start gap-3 rounded-md border px-3 py-2 text-sm"
                >
                  <StatusIcon status={check.status} />
                  <div>
                    <div className="font-medium">{check.name}</div>
                    <div className="text-muted-foreground">{check.detail}</div>
                  </div>
                </div>
              ))}
            </div>
          </section>

          <section>
            <h2 className="mb-3 text-lg font-semibold">PBR policies (pundef-pc)</h2>
            <div className="overflow-x-auto rounded-md border">
              <table className="w-full text-left text-sm">
                <thead className="border-b bg-muted/30">
                  <tr>
                    <th className="px-3 py-2 font-medium">Policy</th>
                    <th className="px-3 py-2 font-medium">Interface</th>
                  </tr>
                </thead>
                <tbody>
                  {snapshot.policies.map((p) => (
                    <tr key={p.name} className="border-b border-border/50 last:border-0">
                      <td className="px-3 py-2 font-mono text-xs">{p.name}</td>
                      <td className="px-3 py-2">{p.interface}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>
        </>
      )}
    </main>
  );
}
