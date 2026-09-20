import { defineConfig } from "@playwright/test";
import { fileURLToPath } from "node:url";
process.env.TMPDIR = fileURLToPath(new URL("../tmp/", import.meta.url));
export default defineConfig({
  testDir: "./tests",
  testMatch: "*.spec.js",
  fullyParallel: false,
  workers: 1,
  use: {
    baseURL: "http://localhost:10015",
    headless: true,
    viewport: { width: 1440, height: 1050 },
    trace: "retain-on-failure",
  },
  webServer: {
    command: "node tests/fixture-server.js",
    url: "http://localhost:10015/api/status",
    reuseExistingServer: false,
  },
  outputDir: "../tmp/ui-results",
  reporter: "list",
});
