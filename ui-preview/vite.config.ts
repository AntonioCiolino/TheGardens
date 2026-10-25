import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

export default defineConfig({
  plugins: [react()],
  server: {
    host: true,
    port: 3847,
    // Allow Cloudflare quick-tunnel hostnames for phone preview
    allowedHosts: true,
  },
});
