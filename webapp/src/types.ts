export type Label = {
  id: string;
  name: string;
  type: string;
  color?: { backgroundColor: string; textColor: string };
};
export type Message = {
  id: string;
  threadId: string;
  from: string;
  to: string;
  cc: string;
  subject: string;
  snippet: string;
  date: number;
  labelIds: string[];
  hasAttachments: boolean;
  calendar: boolean;
};
export type Detail = Message & {
  headers: { name: string; value: string }[];
  plain: string;
  html: string | null;
  remoteImages: boolean;
  attachments: {
    partId: string;
    name: string;
    size: number;
    mimeType: string;
    inline: boolean;
  }[];
};
export type SavedView = { id: string; name: string; query: string };
export const defaults: SavedView[] = [
  { id: "primary", name: "Primary", query: "in:inbox" },
  { id: "today", name: "Today", query: "in:inbox after:{today}" },
  { id: "unread", name: "Unread", query: "in:inbox is:unread" },
  ...["Yellow", "Red", "Green", "Blue", "Purple"].map((c) => ({
    id: c.toLowerCase(),
    name: c,
    query: `has:${c.toLowerCase()}-star`,
  })),
  { id: "investors", name: "Investors", query: "label:Investors" },
];
export function loadViews(): SavedView[] {
  try {
    const v = JSON.parse(localStorage.getItem("amail.views.v1") || "null");
    if (
      Array.isArray(v) &&
      v.length > 0 &&
      v.length <= 30 &&
      v.every(
        (x) =>
          typeof x.id === "string" &&
          typeof x.name === "string" &&
          x.name.trim() &&
          typeof x.query === "string" &&
          x.query.trim(),
      ) &&
      new Set(v.map((x) => x.id)).size === v.length
    )
      return v;
  } catch {
    /* Use defaults if local settings are malformed or unavailable. */
  }
  return defaults;
}
export function expandQuery(query: string) {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  return query.replaceAll("{today}", String(Math.floor(d.getTime() / 1000)));
}
export const senderName = (from: string) =>
  (from.includes("<")
    ? from.slice(0, from.indexOf("<")).trim().replace(/^"|"$/g, "")
    : from) || from;
export function dayName(date: number) {
  const d = new Date(date);
  const today = new Date();
  const yesterday = new Date();
  yesterday.setDate(today.getDate() - 1);
  return d.toDateString() === today.toDateString()
    ? "Today"
    : d.toDateString() === yesterday.toDateString()
      ? "Yesterday"
      : d.toLocaleDateString(undefined, {
          weekday: "long",
          month: "short",
          day: "numeric",
          year: d.getFullYear() !== today.getFullYear() ? "numeric" : undefined,
        });
}
