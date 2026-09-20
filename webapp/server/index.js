import path from "node:path";
import os from "node:os";
import { fileURLToPath } from "node:url";
import { Gmail } from "./gmail.js";
import { createApp } from "./app.js";
import { activityLogger } from "./activity.js";
const webapp = fileURLToPath(new URL("../", import.meta.url));
const log = activityLogger(path.join(webapp, ".private/api-activity.jsonl"));
const gmail = new Gmail({
  log,
  credentialPath:
    process.env.AMAIL_CLIENT_SECRET ||
    path.join(
      os.homedir(),
      "src/aMail/webapp/client_secret_293210038341-j7gm5dkepijelhi9sf85e4i7hbhn2sr1.apps.googleusercontent.com.json",
    ),
  tokenPath: path.join(webapp, ".private/tokens.json"),
});
await gmail.load();
createApp(gmail, { log }).listen(10014, "127.0.0.1", () =>
  console.log("aMail read-only client: http://localhost:10014"),
);
