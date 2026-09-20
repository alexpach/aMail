const b64 = (value) => Buffer.from(value).toString("base64url");
export const raster =
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j3ioAAAAASUVORK5CYII=";
export function fixture(id = "m1", extra = {}) {
  return {
    id,
    threadId: id,
    labelIds: ["INBOX", "UNREAD", "STARRED", "Label_1"],
    internalDate: String(Date.now() - 300000),
    snippet:
      "The plans for next week are ready. Looking forward to seeing you.",
    payload: {
      mimeType: "multipart/mixed",
      headers: [
        { name: "Subject", value: "A little room for what matters" },
        { name: "From", value: "Morgan Chen <morgan@example.test>" },
        { name: "To", value: "alex@example.test" },
        { name: "Message-ID", value: "<fixture@example.test>" },
      ],
      parts: [
        {
          partId: "0",
          mimeType: "multipart/alternative",
          parts: [
            {
              partId: "0.0",
              mimeType: "text/plain",
              body: {
                data: b64(
                  "Hello Alex,\nThe plans for next week are ready.\nMorgan",
                ),
              },
            },
            {
              partId: "0.1",
              mimeType: "text/html",
              body: {
                data: b64(
                  '<div style="max-width:620px;margin:20px;color:#343c49"><h1 style="font-size:28px">A little room for what matters.</h1><p>Hello Alex,</p><p>The plans for next week are ready. A calmer inbox makes it easier to focus on the conversations that count.</p><p>Looking forward to seeing you,<br>Morgan</p><img src="cid:logo" alt="Inline mark"><img src="https://tracking.example.test/pixel" alt="Remote image"><script>window.parent.pwned=true</script><img src=x onerror="window.parent.pwned=true"><form action="https://evil.test"><input value="bad"></form></div>',
                ),
              },
            },
          ],
        },
        {
          partId: "1",
          filename: "agenda.pdf",
          mimeType: "application/pdf",
          body: { attachmentId: "att1", size: 18000 },
        },
        {
          partId: "2",
          filename: "logo.png",
          mimeType: "image/png",
          headers: [{ name: "Content-ID", value: "<logo>" }],
          body: {
            data: Buffer.from(raster, "base64").toString("base64url"),
            size: 68,
          },
        },
        {
          partId: "3",
          mimeType: "text/calendar",
          body: { data: b64("BEGIN:VCALENDAR\r\nEND:VCALENDAR"), size: 30 },
        },
      ],
    },
    ...extra,
  };
}
export function fixtureMailbox() {
  const senders = [
    "Morgan Chen",
    "Studio North",
    "Clara Williams",
    "The Sunday Edit",
    "Daniel Park",
    "Noah at Linear",
    "Open Source Weekly",
    "Sam Rivera",
    "Figma",
    "Maya Patel",
    "Oliver Hayes",
    "Acme Finance",
  ];
  const subjects = [
    "A little room for what matters",
    "September design review",
    "A few notes from our conversation",
    "Your weekly reading list",
    "Re: Next steps for the launch",
    "Your workspace digest",
    "This week in open source",
    "Coffee next week?",
    "Your latest file is ready",
    "An introduction worth making",
    "Invitation: Product catch-up",
    "Your September receipt",
  ];
  return Array.from({ length: 26 }, (_, i) => {
    const m = fixture(`m${i + 1}`);
    m.payload.headers[0].value = subjects[i % subjects.length];
    m.payload.headers[1].value = `${senders[i % senders.length]} <sender${i}@example.test>`;
    m.internalDate = String(
      Date.now() - (i < 10 ? (i + 1) * 1200000 : 86400000 + i * 1200000),
    );
    m.labelIds = [
      "INBOX",
      ...(i % 4 === 0 ? ["UNREAD"] : []),
      ...(i % 5 === 0 ? ["STARRED"] : []),
      ...(i % 3 === 0 ? ["Label_1"] : []),
      ...(i % 7 === 0 ? ["Label_2"] : []),
    ];
    if (i % 3 !== 0) m.payload.parts = m.payload.parts.slice(0, 1);
    return m;
  });
}
