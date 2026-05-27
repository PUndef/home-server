export const DROPS_CDN_URL =
  "https://warframe-web-assets.nyc3.cdn.digitaloceanspaces.com/uploads/cms/hnfvc0o3jnfvc873njb03enrf56.html";

/** Dev proxy path (see vite.config.ts). */
export const DROPS_FETCH_URL = import.meta.env.DEV ? "/drops-source" : DROPS_CDN_URL;

export const CACHE_KEY = "wf-farm-helper-drops-cache-v1";

export const ROTATION_MINUTES: Record<string, number> = {
  A: 5,
  B: 10,
  C: 20,
};
