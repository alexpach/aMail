import fs from "node:fs/promises";
import path from "node:path";

// Explicit fields only. Never persist URLs, query values, IDs, headers or bodies.
const fields = [
  "event",
  "operation",
  "status",
  "reason",
  "durationMs",
  "quotaUnits",
  "unitsLastMinute",
  "retryAfterSeconds",
  "code",
];
export function activityLogger(filename, maxBytes = 2 * 1024 * 1024) {
  let queue = Promise.resolve();
  const log = (entry) => {
    const safe = { time: new Date().toISOString() };
    for (const field of fields)
      if (entry[field] !== undefined) safe[field] = entry[field];
    queue = queue
      .then(async () => {
        await fs.mkdir(path.dirname(filename), {
          recursive: true,
          mode: 0o700,
        });
        const size = await fs
          .stat(filename)
          .then((s) => s.size)
          .catch(() => 0);
        if (size >= maxBytes) await fs.rename(filename, `${filename}.1`);
        await fs.appendFile(filename, `${JSON.stringify(safe)}\n`, {
          mode: 0o600,
        });
      })
      .catch(() =>
        console.error(
          "aMail activity log could not be written. Check local file permissions.",
        ),
      );
  };
  log.flush = () => queue;
  return log;
}
