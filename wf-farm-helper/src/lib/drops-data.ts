import { CACHE_KEY, DROPS_FETCH_URL } from "@/lib/constants";
import { parseDropsHtml, type DropsDataset } from "@/lib/parse-drops";

type CachePayload = {
  lastUpdate: string | null;
  html: string;
  fetchedAt: number;
};

let memoryCache: DropsDataset | null = null;

function readCache(): CachePayload | null {
  try {
    const raw = localStorage.getItem(CACHE_KEY);
    if (!raw) return null;
    return JSON.parse(raw) as CachePayload;
  } catch {
    return null;
  }
}

function writeCache(payload: CachePayload) {
  try {
    localStorage.setItem(CACHE_KEY, JSON.stringify(payload));
  } catch {
    // ignore quota errors
  }
}

async function fetchHtml(): Promise<{ html: string; fromCache: boolean }> {
  const cached = readCache();
  const urls = [DROPS_FETCH_URL, `${import.meta.env.BASE_URL}drops.html`];
  let lastError: Error | null = null;

  for (const url of urls) {
    try {
      const response = await fetch(url, { cache: "no-cache" });
      if (!response.ok) {
        lastError = new Error(`HTTP ${response.status} for ${url}`);
        continue;
      }
      const html = await response.text();
      if (html.length < 1000) {
        lastError = new Error(`Слишком короткий ответ: ${url}`);
        continue;
      }
      const parsed = parseDropsHtml(html);
      writeCache({
        html,
        lastUpdate: parsed.lastUpdate,
        fetchedAt: Date.now(),
      });
      return { html, fromCache: false };
    } catch (err) {
      lastError = err instanceof Error ? err : new Error(String(err));
    }
  }

  if (cached) return { html: cached.html, fromCache: true };
  throw lastError ?? new Error("Не удалось загрузить список дропов");
}

export type LoadResult = {
  dataset: DropsDataset;
  fromCache: boolean;
  usedStaleCache: boolean;
};

export async function loadDropsDataset(force = false): Promise<LoadResult> {
  if (!force && memoryCache) {
    return { dataset: memoryCache, fromCache: true, usedStaleCache: false };
  }

  let usedStaleCache = false;
  try {
    const { html, fromCache } = await fetchHtml();
    memoryCache = parseDropsHtml(html);
    return { dataset: memoryCache, fromCache, usedStaleCache: false };
  } catch (error) {
    const cached = readCache();
    if (cached) {
      memoryCache = parseDropsHtml(cached.html);
      usedStaleCache = true;
      return { dataset: memoryCache, fromCache: true, usedStaleCache: true };
    }
    throw error;
  }
}

export function clearDropsCache() {
  memoryCache = null;
  localStorage.removeItem(CACHE_KEY);
}
