// Isolated UI-test server. No credentials or real Gmail client are loaded here.
import { createApp } from "../server/app.js";
import { SCOPE } from "../server/gmail.js";
import { fixtureMailbox } from "./fixtures.js";
const mailbox = fixtureMailbox();
const labels = [
  { id: "INBOX", name: "INBOX", type: "system" },
  {
    id: "Label_1",
    name: "Projects",
    type: "user",
    color: { backgroundColor: "#dceade", textColor: "#4c7955" },
  },
  {
    id: "Label_2",
    name: "Investors",
    type: "user",
    color: { backgroundColor: "#e7def9", textColor: "#796199" },
  },
];
const fake = {
  token: { scope: SCOPE },
  credentials: async () => ({ client_id: "test", client_secret: "test" }),
  get: async (resource, params) => {
    if (resource === "profile") return { emailAddress: "alex@example.test" };
    if (resource === "labels") return { labels };
    if (resource.startsWith("labels/"))
      return labels.find((l) => l.id === resource.split("/")[1]);
    if (resource === "messages")
      return {
        messages: (params.pageToken ? mailbox.slice(0, 2) : mailbox).map(
          (m) => ({ id: m.id }),
        ),
        nextPageToken: params.pageToken ? undefined : "second",
        resultSizeEstimate: 102,
      };
    if (resource.includes("/attachments/"))
      return {
        data: Buffer.from("%PDF test attachment").toString("base64url"),
      };
    if (resource.startsWith("messages/"))
      return params?.format === "raw"
        ? {
            raw: Buffer.from(
              "Subject: A little room for what matters\r\nFrom: Morgan <morgan@example.test>\r\n\r\nSynthetic email for testing.",
            ).toString("base64url"),
          }
        : mailbox.find((m) => m.id === resource.split("/")[1]);
    throw new Error("Unexpected fixture request");
  },
};
createApp(fake, { origin: "http://localhost:10015" }).listen(
  10015,
  "127.0.0.1",
);
