/**
 * Static-sites URL routing — single source for all Vite apps via @shared alias.
 */

export const SITE_URLS = {
  warframe: { path: "/warframe/", host: "http://warframe.home/" },
  requiem: { path: "/requiem/", host: "http://requiem.home/" },
  wfFarm: { path: "/wf-farm/", host: "http://wffarm.home/" },
  wfTwitch: { path: "/wf-twitch/", host: "http://wftwitch.home/" },
  networkRouting: { path: "/network-routing/", host: "http://network.home/" },
} as const;

/** Public HTTPS edge (Apache nextcloud-vm → Caddy static-sites). */
export const SITE_EDGE_ORIGIN = "https://apps-pundef.mooo.com";

export type SiteApp = keyof typeof SITE_URLS;

const LAN_HOSTNAMES = new Set<string>(["warframe.home", "requiem.home", "wffarm.home", "wftwitch.home", "network.home"]);

/** Apps on *.home vhosts are served from /; apps-pundef and IP use /warframe/, /requiem/, etc. */
export function usesHostnameRouting(): boolean {
  return LAN_HOSTNAMES.has(window.location.hostname);
}

/** Resolve link target: path on current origin (public edge) or full .home URL (LAN). */
export function siteUrl(app: SiteApp): string {
  const entry = SITE_URLS[app];
  return usesHostnameRouting() ? entry.host : entry.path;
}

/** Canonical HTTPS URL on the public edge (needed for browser APIs like Notification). */
export function siteEdgeUrl(app: SiteApp): string {
  return `${SITE_EDGE_ORIGIN}${SITE_URLS[app].path}`;
}
