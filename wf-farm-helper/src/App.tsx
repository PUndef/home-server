import { useEffect, useMemo, useState } from "react";
import { IconRefresh } from "@tabler/icons-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { clearDropsCache, loadDropsDataset } from "@/lib/drops-data";
import type { DropsDataset } from "@/lib/parse-drops";
import { formatEfficiency, rankMatches, speedTierLabel, type FarmMatch } from "@/lib/search";
import { cn } from "@/lib/utils";

const FILTERS_KEY = "wf-farm-helper-filters-v1";

type Filters = {
  missionsOnly: boolean;
  hideEvents: boolean;
  hideConclave: boolean;
};

function loadFilters(): Filters {
  try {
    const raw = localStorage.getItem(FILTERS_KEY);
    if (!raw) {
      return { missionsOnly: true, hideEvents: true, hideConclave: true };
    }
    return { missionsOnly: true, hideEvents: true, hideConclave: true, ...JSON.parse(raw) };
  } catch {
    return { missionsOnly: true, hideEvents: true, hideConclave: true };
  }
}

function speedBadgeVariant(tier: FarmMatch["speedTier"]): "default" | "secondary" | "outline" {
  if (tier === "fast") return "default";
  if (tier === "slow") return "secondary";
  return "outline";
}

function locationLabel(match: FarmMatch) {
  const { source } = match;
  if (source.planet && source.node) return `${source.planet} / ${source.node}`;
  return source.label;
}

function FilterToggle({
  checked,
  label,
  onChange,
}: {
  checked: boolean;
  label: string;
  onChange: (checked: boolean) => void;
}) {
  return (
    <label
      className={cn(
        "flex cursor-pointer items-center gap-2 rounded-md border bg-input/20 px-3 py-2 text-sm transition hover:bg-muted",
        checked && "border-primary/30 bg-muted",
      )}
    >
      <input checked={checked} className="size-4 accent-primary" type="checkbox" onChange={(e) => onChange(e.target.checked)} />
      {label}
    </label>
  );
}

export default function App() {
  const [dataset, setDataset] = useState<DropsDataset | null>(null);
  const [query, setQuery] = useState("");
  const [filters, setFilters] = useState<Filters>(loadFilters);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState<string | null>(null);

  useEffect(() => {
    localStorage.setItem(FILTERS_KEY, JSON.stringify(filters));
  }, [filters]);

  async function refresh(force = false) {
    setLoading(true);
    setError(null);
    try {
      if (force) clearDropsCache();
      const result = await loadDropsDataset(force);
      setDataset(result.dataset);
      const parts = [
        result.dataset.lastUpdate ? `╨┤╨░╨╜╨╜╤ï╨╡ ╨╛╤é ${result.dataset.lastUpdate}` : "╨┤╨░╤é╨░ ╨╛╨▒╨╜╨╛╨▓╨╗╨╡╨╜╨╕╤Å ╨╜╨╡ ╨╜╨░╨╣╨┤╨╡╨╜╨░",
        `${result.dataset.sources.length} ╨╕╤ü╤é╨╛╤ç╨╜╨╕╨║╨╛╨▓`,
      ];
      if (result.usedStaleCache) parts.push("╨╛╤ä╨╗╨░╨╣╨╜-╨║╤ì╤ê");
      setStatus(parts.join(" ┬╖ "));
    } catch (err) {
      setError(err instanceof Error ? err.message : "╨₧╤ê╨╕╨▒╨║╨░ ╨╖╨░╨│╤Ç╤â╨╖╨║╨╕");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void refresh();
  }, []);

  const matches = useMemo(() => {
    if (!dataset || query.trim().length < 2) return [];
    return rankMatches(dataset, query, filters);
  }, [dataset, query, filters]);

  const suggestions = useMemo(() => {
    if (!dataset || query.trim().length < 1) return [];
    const q = query.trim().toLowerCase();
    return Array.from(dataset.itemIndex.keys())
      .filter((key) => key.includes(q))
      .slice(0, 12);
  }, [dataset, query]);

  return (
    <main className="mx-auto min-h-screen w-full max-w-6xl px-4 py-8 sm:px-6">
      <header className="mb-6 text-center">
        <Badge variant="outline" className="mb-3 border-primary/30 text-primary">
          Warframe PC Drops
        </Badge>
        <h1 className="text-3xl font-bold tracking-tight sm:text-4xl">WF Farm Helper</h1>
        <p className="mx-auto mt-3 max-w-2xl text-base text-muted-foreground">
          ╨ƒ╨╛╨╕╤ü╨║ ╨▓╤ï╨│╨╛╨┤╨╜╤ï╤à ╨╝╨╕╤ü╤ü╨╕╨╣ ╨┐╨╛ ╨╛╤ä╨╕╤å╨╕╨░╨╗╤î╨╜╨╛╨╝╤â ╤ü╨┐╨╕╤ü╨║╤â ╨┤╤Ç╨╛╨┐╨╛╨▓. ╨á╨░╨╜╨╢╨╕╤Ç╨╛╨▓╨░╨╜╨╕╨╡ ╨┐╨╛ ╤ê╨░╨╜╤ü╤â, ╨║╨╛╨╗╨╕╤ç╨╡╤ü╤é╨▓╤â ╨╕
          ╨╛╤å╨╡╨╜╨╛╤ç╨╜╨╛╨╝╤â ╨▓╤Ç╨╡╨╝╨╡╨╜╨╕ ΓÇö ╨┤╨░╨╜╨╜╤ï╨╡ ╨╛╨▒╨╜╨╛╨▓╨╗╤Å╤Ä╤é╤ü╤Å ╤ü CDN ╨┐╤Ç╨╕ ╨║╨░╨╢╨┤╨╛╨╝ ╨╛╤é╨║╤Ç╤ï╤é╨╕╨╕.
        </p>
      </header>

      <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_280px] lg:items-start">
        <div className="space-y-6">
          <Card>
            <CardHeader>
              <CardTitle>╨º╤é╨╛ ╤ä╨░╤Ç╨╝╨╕╤é╤î?</CardTitle>
              <CardDescription>
                ╨á╨╡╤ü╤â╤Ç╤ü, ╨╝╨╛╨┤, ╤Ç╨╡╨╗╨╕╨║ ╨╕╨╗╨╕ ╤ç╨╡╤Ç╤é╤æ╨╢ ΓÇö ╨╜╨░╨┐╤Ç╨╕╨╝╨╡╤Ç polymer, nitain, serration.
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
                <input
                  className="h-9 flex-1 rounded-md border bg-input/20 px-3 text-sm outline-none transition focus-visible:border-ring focus-visible:ring-2 focus-visible:ring-ring/30"
                  placeholder="╨¥╨░╨╖╨▓╨░╨╜╨╕╨╡ ╨┤╤Ç╨╛╨┐╨░..."
                  value={query}
                  onChange={(e) => setQuery(e.target.value)}
                />
                <Button disabled={loading} type="button" variant="outline" onClick={() => void refresh(true)}>
                  <IconRefresh className={cn(loading && "animate-spin")} />
                  ╨₧╨▒╨╜╨╛╨▓╨╕╤é╤î
                </Button>
              </div>

              {suggestions.length > 0 && query.length > 0 && (
                <div className="flex flex-wrap gap-2">
                  {suggestions.map((item) => (
                    <Button key={item} size="xs" type="button" variant="secondary" onClick={() => setQuery(item)}>
                      {item}
                    </Button>
                  ))}
                </div>
              )}

              <fieldset className="rounded-md border bg-input/20 p-3">
                <legend className="px-1 text-xs font-medium text-muted-foreground">╨ñ╨╕╨╗╤î╤é╤Ç╤ï</legend>
                <div className="mt-2 flex flex-wrap gap-2">
                  <FilterToggle
                    checked={filters.missionsOnly}
                    label="╨ó╨╛╨╗╤î╨║╨╛ ╨╝╨╕╤ü╤ü╨╕╨╕ / ╨▒╨░╤â╨╜╤é╨╕"
                    onChange={(missionsOnly) => setFilters((f) => ({ ...f, missionsOnly }))}
                  />
                  <FilterToggle
                    checked={filters.hideEvents}
                    label="╨í╨║╤Ç╤ï╤é╤î Event"
                    onChange={(hideEvents) => setFilters((f) => ({ ...f, hideEvents }))}
                  />
                  <FilterToggle
                    checked={filters.hideConclave}
                    label="╨í╨║╤Ç╤ï╤é╤î Conclave"
                    onChange={(hideConclave) => setFilters((f) => ({ ...f, hideConclave }))}
                  />
                </div>
              </fieldset>

              {loading && <p className="text-sm text-muted-foreground">╨ù╨░╨│╤Ç╤â╨╖╨║╨░ ╨╕ ╤Ç╨░╨╖╨▒╨╛╤Ç ╤é╨░╨▒╨╗╨╕╤åΓÇª</p>}
              {error && <p className="text-sm text-destructive">{error}</p>}
            </CardContent>
          </Card>

          {query.trim().length >= 2 && !loading && (
            <Card>
              <CardHeader>
                <CardTitle>╨á╨╡╨╖╤â╨╗╤î╤é╨░╤é╤ï ({matches.length})</CardTitle>
                <CardDescription>
                  ╨í╨╛╤Ç╤é╨╕╤Ç╨╛╨▓╨║╨░: ╨╛╨╢╨╕╨┤╨░╨╡╨╝╤ï╨╣ ╨┤╤Ç╨╛╨┐ ╨╖╨░ ╨┐╤Ç╨╛╨│╨╛╨╜ ├╖ ╨╝╨╕╨╜╤â╤é╤ï. ╨Æ╤ï╤ê╨╡ ╤Ç╨╡╨╣╤é╨╕╨╜╨│ ΓÇö ╨▓╤ï╨│╨╛╨┤╨╜╨╡╨╡ ╨┐╤Ç╨╕ ╤é╨╛╨╝ ╨╢╨╡ ╨▓╤Ç╨╡╨╝╨╡╨╜╨╕.
                </CardDescription>
              </CardHeader>
              <CardContent className="overflow-x-auto">
                {matches.length === 0 ? (
                  <p className="text-sm text-muted-foreground">
                    ╨¥╨╕╤ç╨╡╨│╨╛ ╨╜╨╡ ╨╜╨░╨╣╨┤╨╡╨╜╨╛. ╨ƒ╨╛╨┐╤Ç╨╛╨▒╤â╨╣╤é╨╡ ╨┤╤Ç╤â╨│╨╛╨╡ ╨╕╨╝╤Å ╨╕╨╗╨╕ ╤ü╨╜╨╕╨╝╨╕╤é╨╡ ╤ä╨╕╨╗╤î╤é╤Ç╤ï.
                  </p>
                ) : (
                  <table className="w-full min-w-[720px] border-collapse text-left text-sm">
                    <thead>
                      <tr className="border-b border-border text-muted-foreground">
                        <th className="py-2 pr-3 font-medium">#</th>
                        <th className="py-2 pr-3 font-medium">╨¢╨╛╨║╨░╤å╨╕╤Å</th>
                        <th className="py-2 pr-3 font-medium">╨ó╨╕╨┐</th>
                        <th className="py-2 pr-3 font-medium">╨ö╤Ç╨╛╨┐</th>
                        <th className="py-2 pr-3 font-medium">╨¿╨░╨╜╤ü</th>
                        <th className="py-2 pr-3 font-medium">~╨╝╨╕╨╜</th>
                        <th className="py-2 pr-3 font-medium">╨ó╨╡╨╝╨┐</th>
                        <th className="py-2 font-medium">╨á╨╡╨╣╤é╨╕╨╜╨│</th>
                      </tr>
                    </thead>
                    <tbody>
                      {matches.slice(0, 80).map((match, index) => (
                        <tr
                          key={`${match.source.label}-${match.drop.item}-${match.drop.rotation}-${index}`}
                          className="border-b border-border/60 transition-colors hover:bg-muted/30"
                        >
                          <td className="py-2.5 pr-3 text-muted-foreground">{index + 1}</td>
                          <td className="py-2.5 pr-3 font-medium">{locationLabel(match)}</td>
                          <td className="py-2.5 pr-3">
                            <div>{match.source.missionType ?? match.source.section}</div>
                            {match.drop.rotation && (
                              <span className="text-xs text-muted-foreground">╤Ç╨╛╤é╨░╤å╨╕╤Å {match.drop.rotation}</span>
                            )}
                          </td>
                          <td className="py-2.5 pr-3">{match.drop.item}</td>
                          <td className="py-2.5 pr-3">
                            {match.drop.chance.percent.toFixed(2)}%
                            <span className="block text-xs text-muted-foreground">{match.drop.chance.rarity}</span>
                          </td>
                          <td className="py-2.5 pr-3">{match.minutes}</td>
                          <td className="py-2.5 pr-3">
                            <Badge variant={speedBadgeVariant(match.speedTier)}>{speedTierLabel(match.speedTier)}</Badge>
                          </td>
                          <td className="py-2.5 font-mono text-xs">{formatEfficiency(match.efficiency)}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                )}
                {matches.length > 80 && (
                  <p className="mt-3 text-xs text-muted-foreground">╨ƒ╨╛╨║╨░╨╖╨░╨╜╤ï ╨┐╨╡╤Ç╨▓╤ï╨╡ 80 ╨╕╨╖ {matches.length}.</p>
                )}
              </CardContent>
            </Card>
          )}
        </div>

        <Card size="sm" className="lg:sticky lg:top-6">
          <CardHeader>
            <CardTitle>╨í╤é╨░╤é╤â╤ü</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3 text-sm text-muted-foreground">
            {status ? <p>{status}</p> : <p>╨¥╨╡╤é ╨┤╨░╨╜╨╜╤ï╤à</p>}
            <p className="text-xs leading-relaxed">
              ╨ÿ╤ü╤é╨╛╤ç╨╜╨╕╨║:{" "}
              <a
                className="text-primary underline-offset-4 hover:underline"
                href="https://warframe-web-assets.nyc3.cdn.digitaloceanspaces.com/uploads/cms/hnfvc0o3jnfvc873njb03enrf56.html"
                rel="noreferrer"
                target="_blank"
              >
                Warframe PC Drops
              </a>
              . ╨₧╤å╨╡╨╜╨║╨╕ ╨▓╤Ç╨╡╨╝╨╡╨╜╨╕ ╨╝╨╕╤ü╤ü╨╕╨╣ ╨┐╤Ç╨╕╨▒╨╗╨╕╨╖╨╕╤é╨╡╨╗╤î╨╜╤ï╨╡.
            </p>
          </CardContent>
        </Card>
      </div>
    </main>
  );
}
