import path from "node:path";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import { defineConfig } from "vite";

const DROPS_PATH = "/uploads/cms/hnfvc0o3jnfvc873njb03enrf56.html";
const DROPS_HOST = "https://warframe-web-assets.nyc3.cdn.digitaloceanspaces.com";

export default defineConfig({
  base: "./",
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
  server: {
    proxy: {
      "/drops-source": {
        target: DROPS_HOST,
        changeOrigin: true,
        rewrite: () => DROPS_PATH,
      },
    },
  },
});
