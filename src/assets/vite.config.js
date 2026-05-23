import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import path from "path";

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src")
    }
  },
  build: {
    outDir: "../priv/static/assets",
    emptyOutDir: true,
    manifest: false,
    rollupOptions: {
      input: "src/main.jsx",
      output: {
        entryFileNames: "app.js",
        chunkFileNames: "[name]-[hash].js",
        assetFileNames: (info) => {
          if (info.name && info.name.endsWith(".css")) return "app.css";
          return "[name]-[hash][extname]";
        }
      }
    }
  },
  server: {
    port: 5173,
    strictPort: true,
    origin: "http://localhost:5173"
  }
});
