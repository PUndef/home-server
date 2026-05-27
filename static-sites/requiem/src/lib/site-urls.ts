/**
 * Static-sites URL routing. Keep in sync with static-sites/shared/site-urls.ts
 */

export const SITE_URLS = {
  warframe: { path: "/warframe/", host: "http://warframe.home/" },
  requiem: { path: "/requiem/", host: "http://requiem.home/" },
  wfFarm: { path: "/wf-farm/", host: "http://wffarm.home/" },
} as const;

export type SiteApp = keyof typeof SITE_URLS;

const LAN_HOSTNAMES = new Set<string>(["warframe.home", "requiem.home", "wffarm.home"]);

/** Apps on *.home vhosts are served from /; apps-pundef and IP use /warframe/, /requiem/, etc. */
export function usesHostnameRouting(): boolean {
  return LAN_HOSTNAMES.has(window.location.hostname);
}

/** Resolve link target: path on current origin (public edge) or full .home URL (LAN). */
export function siteUrl(app: SiteApp): string {
  const entry = SITE_URLS[app];
  return usesHostnameRouting() ? entry.host : entry.path;
}
