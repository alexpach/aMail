import sanitizeHtml from "sanitize-html";
import iconv from "iconv-lite";
import libmime from "libmime";
export const header = (part, name) =>
  (part?.headers ?? []).find((h) => h.name.toLowerCase() === name.toLowerCase())
    ?.value ?? "";
export const bytes = (data) => Buffer.from(data ?? "", "base64url");
export function partsOf(part) {
  if (!part) return [];
  // Encapsulated messages are attachments, not the enclosing message's body.
  if (part.mimeType === "message/rfc822") return [part];
  return [part, ...(part.parts ?? []).flatMap(partsOf)];
}
const isAttachment = (p) =>
  !!p.filename ||
  /^attachment/i.test(header(p, "content-disposition")) ||
  ["message/rfc822", "text/calendar"].includes(p.mimeType);
export function summarize(message) {
  const p = message.payload;
  const parts = partsOf(p);
  const decoded = (name) => libmime.decodeWords(header(p, name));
  return {
    id: message.id,
    threadId: message.threadId,
    subject: decoded("subject") || "(no subject)",
    from: decoded("from"),
    to: decoded("to"),
    cc: decoded("cc"),
    date: Number(message.internalDate),
    snippet: message.snippet ?? "",
    labelIds: message.labelIds ?? [],
    hasAttachments: parts.some(isAttachment),
    calendar: parts.some(
      (p) => p.mimeType === "text/calendar" || /\.ics$/i.test(p.filename ?? ""),
    ),
  };
}
export function decodeText(part, data) {
  const charset =
    /charset\s*=\s*["']?([^\s;"']+)/i.exec(header(part, "content-type"))?.[1] ||
    "utf-8";
  return iconv.decode(
    bytes(data),
    iconv.encodingExists(charset) ? charset : "utf-8",
  );
}
export function cleanHtml(html, { inline = new Map(), remote = false } = {}) {
  return sanitizeHtml(html, {
    allowedTags: [
      "p",
      "br",
      "div",
      "span",
      "a",
      "b",
      "strong",
      "i",
      "em",
      "u",
      "s",
      "blockquote",
      "pre",
      "code",
      "h1",
      "h2",
      "h3",
      "h4",
      "h5",
      "h6",
      "hr",
      "ul",
      "ol",
      "li",
      "table",
      "thead",
      "tbody",
      "tfoot",
      "tr",
      "td",
      "th",
      "img",
      "center",
      "font",
      "sup",
      "sub",
    ],
    allowedAttributes: {
      "*": ["style", "dir", "align"],
      a: ["href", "target", "rel"],
      img: ["src", "alt", "width", "height"],
      td: ["colspan", "rowspan", "width", "height"],
      th: ["colspan", "rowspan"],
      table: ["width", "cellpadding", "cellspacing", "border"],
      font: ["color", "size", "face"],
    },
    allowedSchemes: ["https", "http", "mailto"],
    allowedSchemesByTag: { img: ["data", ...(remote ? ["https"] : [])] },
    allowProtocolRelative: false,
    allowedStyles: {
      "*": {
        color: [/^#[\da-f]{3,8}$/i, /^rgb\([\d\s,.%]+\)$/i, /^[a-z]+$/i],
        "background-color": [
          /^#[\da-f]{3,8}$/i,
          /^rgb\([\d\s,.%]+\)$/i,
          /^[a-z]+$/i,
        ],
        "font-size": [/^[\d.]+(?:px|pt|em|rem|%)$/],
        "font-family": [/^[\w\s,"'-]+$/],
        "font-weight": [/^(?:normal|bold|[1-9]00)$/],
        "text-align": [/^(?:left|right|center|justify)$/],
        "text-decoration": [/^(?:underline|line-through|none)$/],
        "font-style": [/^(?:italic|normal)$/],
        "line-height": [/^[\d.]+(?:px|em|%)?$/],
        padding: [/^[\d.\s]+(?:px|em|%)$/],
        margin: [/^[\d.\s]+(?:px|em|%)$/],
        width: [/^[\d.]+(?:px|%)$/],
        "max-width": [/^[\d.]+(?:px|%)$/],
        height: [/^[\d.]+(?:px|%)$/],
        "border-collapse": [/^(?:collapse|separate)$/],
        "vertical-align": [/^(?:top|middle|bottom)$/],
      },
    },
    transformTags: {
      a: (_, attrs) => ({
        tagName: "a",
        attribs: { ...attrs, target: "_blank", rel: "noopener noreferrer" },
      }),
      img: (_, attrs) => {
        let src = attrs.src ?? "";
        if (/^cid:/i.test(src))
          src = inline.get(src.slice(4).replace(/^<|>$/g, "")) ?? "";
        // Only supplied CID raster images or explicitly enabled HTTPS images.
        if (!(
          [...inline.values()].includes(src) ||
          (remote && /^https:\/\//i.test(src))
        ))
          src = "";
        return src
          ? {
              tagName: "img",
              attribs: { ...attrs, src, alt: attrs.alt || "Email image" },
            }
          : {
              tagName: "span",
              attribs: {},
              text: attrs.alt ? `[${attrs.alt}]` : "",
            };
      },
    },
  });
}
export function frameDocument(html, remote = false) {
  return `<!doctype html><html><head><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:${remote ? " https:" : ""}; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'"><meta name="referrer" content="no-referrer"><style>body{font:15px/1.6 Arial,sans-serif;color:#292d32;margin:16px;overflow-wrap:anywhere}img{max-width:100%;height:auto}table{max-width:100%}pre{white-space:pre-wrap}a{color:#2563eb}</style></head><body>${html}</body></html>`;
}
export async function detail(message, getAttachment, remote = false) {
  const parts = partsOf(message.payload);
  const inline = new Map();
  const attachments = [];
  async function data(p) {
    return (
      p.body?.data ??
      (p.body?.attachmentId
        ? (await getAttachment(p.body.attachmentId)).data
        : "")
    );
  }
  let plain = "",
    html = "";
  for (const p of parts) {
    if (p.parts?.length && p.mimeType !== "message/rfc822") continue;
    const cid = header(p, "content-id").replace(/^<|>$/g, "");
    if (
      isAttachment(p) ||
      cid ||
      (p.body?.attachmentId &&
        !["text/plain", "text/html"].includes(p.mimeType))
    ) {
      attachments.push({
        partId: p.partId ?? "",
        name:
          p.filename ||
          (p.mimeType === "text/calendar" ? "invitation.ics" : "attachment"),
        size: p.body?.size ?? 0,
        mimeType: p.mimeType,
        inline: !!cid,
      });
    }
    if (
      cid &&
      /^image\/(png|jpeg|gif|webp)$/i.test(p.mimeType) &&
      (p.body?.size ?? 0) < 5 * 1024 * 1024
    )
      inline.set(
        cid,
        `data:${p.mimeType};base64,${bytes(await data(p)).toString("base64")}`,
      );
    if (!isAttachment(p)) {
      if (p.mimeType === "text/html" && !html)
        html = decodeText(p, await data(p));
      if (p.mimeType === "text/plain" && !plain)
        plain = decodeText(p, await data(p));
    }
  }
  return {
    ...summarize(message),
    headers: message.payload?.headers ?? [],
    attachments,
    plain,
    html: html
      ? frameDocument(cleanHtml(html, { inline, remote }), remote)
      : null,
    remoteImages: /(?:src|background)\s*=\s*["']?https?:/i.test(html),
  };
}
