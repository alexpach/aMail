import { type ReactNode, useEffect, useRef, useState } from "react";
import {
  Menu as MenuIcon,
  RefreshCw,
  MoreVertical,
  Search,
  X,
  Inbox,
  Star,
  Send,
  FileText,
  ShieldAlert,
  Circle,
  Mail,
  Tag,
  Archive,
  Paperclip,
  ShoppingCart,
  Settings as SettingsIcon,
  ChevronLeft,
  ChevronRight,
  ArrowLeft,
  CalendarDays,
  Trash2,
  Reply,
  LockKeyhole,
  SlidersHorizontal,
  AlertCircle,
  LogIn,
} from "lucide-react";
import { Button } from "./components/spectrum/button";
import { TaskCheckbox } from "./components/spectrum/task-checkbox";
import { IconButton, Menu, MenuItem, Modal } from "./components/controls";
import { Settings } from "./components/Settings";
import {
  type Message,
  type Detail,
  type Label,
  type SavedView,
  loadViews,
  expandQuery,
  senderName,
  dayName,
  defaults,
} from "./types";
type Location = { name: string; query: string; id?: string; label?: string };
type Page = {
  messages: Message[];
  nextPage: string | null;
  unavailable: number;
};
class ApiError extends Error {
  constructor(
    message: string,
    public code: string,
  ) {
    super(message);
  }
}
async function api<T>(url: string, signal?: AbortSignal): Promise<T> {
  const r = await fetch(url, { signal });
  const data = await r.json();
  if (!r.ok) throw new ApiError(data.error || "Request failed.", data.code);
  return data;
}
const colors: Record<string, string> = {
  yellow: "#bc8c00",
  red: "#d34545",
  green: "#259c66",
  blue: "#3979d6",
  purple: "#9660cc",
};
const folders = [
  { name: "Inbox", query: "in:inbox", icon: Inbox },
  { name: "Starred", query: "is:starred", icon: Star },
  { name: "Sent", query: "in:sent", icon: Send },
  { name: "Drafts", query: "in:drafts", icon: FileText },
  { name: "Spam", query: "in:spam", icon: ShieldAlert },
];
const bookmarks = [
  {
    name: "Archived",
    query: "-in:inbox -in:sent -in:drafts -in:spam -in:trash",
    icon: Archive,
  },
  { name: "Attachments", query: "has:attachment", icon: Paperclip },
  { name: "Purchases", query: "category:purchases", icon: ShoppingCart },
];
function SidebarSection({
  name,
  children,
}: {
  name: string;
  children: ReactNode;
}) {
  const key = `amail.sidebar.${name}`;
  const [expanded, setExpanded] = useState(() => {
    try {
      return localStorage.getItem(key) !== "collapsed";
    } catch {
      return true;
    }
  });
  return (
    <section className="sidebar-section">
      <button
        className="section-toggle"
        aria-expanded={expanded}
        aria-controls={`section-${name}`}
        onClick={() => {
          setExpanded(!expanded);
          try {
            localStorage.setItem(key, expanded ? "collapsed" : "expanded");
          } catch {
            /* Keep working without storage. */
          }
        }}
      >
        <ChevronRight size={14} className={expanded ? "rotated" : ""} />
        {name}
      </button>
      <div id={`section-${name}`} hidden={!expanded}>
        {children}
      </div>
    </section>
  );
}
function labelStyle(l: Label) {
  return {
    backgroundColor: l.color?.backgroundColor || "#edf0f4",
    color: l.color?.textColor || "#5e6571",
  };
}
function Badges({
  message,
  labels,
  all = false,
}: {
  message: Message;
  labels: Label[];
  all?: boolean;
}) {
  const shown = message.labelIds
    .map((id) => labels.find((l) => l.id === id))
    .filter(
      (l): l is Label =>
        !!l && (l.type === "user" || (all && l.id === "INBOX")),
    );
  return (
    <span className="badges">
      {shown.slice(0, all ? 20 : 2).map((l) => (
        <span className="badge" key={l.id} title={l.name} style={labelStyle(l)}>
          {l.name === "INBOX" ? "Inbox" : l.name}
        </span>
      ))}
      {!all && shown.length > 2 && (
        <span
          className="badge"
          title={shown
            .slice(2)
            .map((l) => l.name)
            .join(", ")}
        >
          +{shown.length - 2}
        </span>
      )}
    </span>
  );
}
function shortDate(date: number) {
  return new Date(date).toDateString() === new Date().toDateString()
    ? new Date(date).toLocaleTimeString([], {
        hour: "numeric",
        minute: "2-digit",
      })
    : new Date(date).toLocaleDateString([], { month: "short", day: "numeric" });
}
function MailRow({
  m,
  labels,
  selected,
  toggle,
  open,
  starColor,
}: {
  m: Message;
  labels: Label[];
  selected: boolean;
  toggle: () => void;
  open: () => void;
  starColor?: string;
}) {
  const starred = m.labelIds.includes("STARRED");
  return (
    <div
      className={`mail-row ${m.labelIds.includes("UNREAD") ? "unread" : ""} ${selected ? "selected" : ""}`}
    >
      <button
        className="row-open"
        onClick={open}
        aria-label={`Open ${m.subject} from ${senderName(m.from)}`}
      >
        <span
          className={`star ${starred ? "starred" : ""}`}
          title={
            starred
              ? starColor
                ? "Star color inferred from this exact Gmail color filter"
                : "Starred, color unavailable from Gmail API"
              : "Not starred"
          }
          style={starred && starColor ? { color: starColor } : undefined}
        >
          <Star size={17} fill={starred ? "currentColor" : "none"} />
        </span>
        <span className="sender" title={m.from}>
          {senderName(m.from)}
        </span>
        <span className="mail-copy">
          <span className="subject">{m.subject}</span>
          <span className="preview"> · {m.snippet}</span>
        </span>
        <Badges message={m} labels={labels} />
        <span className="indicators">
          {m.hasAttachments && (
            <Paperclip size={15} aria-label="Has attachment" />
          )}
          {m.calendar && (
            <CalendarDays size={15} aria-label="Calendar invitation" />
          )}
        </span>
      </button>
      <div className="row-end">
        <time title={new Date(m.date).toLocaleString()}>
          {shortDate(m.date)}
        </time>
        <div className="row-actions">
          <span title="Delete is unavailable in read-only mode">
            <button disabled aria-label="Delete unavailable in read-only mode">
              <Trash2 size={15} />
            </button>
          </span>
          <span title="Reply is unavailable in read-only mode">
            <button disabled aria-label="Reply unavailable in read-only mode">
              <Reply size={15} />
            </button>
          </span>
          <TaskCheckbox
            checked={selected}
            label={`Select ${m.subject}`}
            onCheckedChange={toggle}
          />
        </div>
      </div>
    </div>
  );
}
function MessageView({
  m,
  labels,
  back,
  showDetails,
  loadRemote,
}: {
  m: Detail;
  labels: Label[];
  back: () => void;
  showDetails: (mode: "headers" | "original") => void;
  loadRemote: () => void;
}) {
  return (
    <article className="message-view">
      <div className="message-toolbar">
        <Button variant="ghost" onClick={back}>
          <ArrowLeft />
          Back to messages
        </Button>
        <span className="readonly-note">
          <LockKeyhole size={12} /> Read only
        </span>
      </div>
      <div className="message-title">
        <h1>{m.subject}</h1>
        <Badges message={m} labels={labels} all />
      </div>
      <div className="message-meta">
        <div className="sender-avatar">
          {senderName(m.from).slice(0, 1).toUpperCase()}
        </div>
        <div className="recipient">
          <strong>{senderName(m.from)}</strong>
          <div className="muted" title={m.from}>
            {m.from}
          </div>
          <button
            className="recipient-details"
            onClick={() => showDetails("headers")}
          >
            to {m.to || "undisclosed recipients"}
            {m.cc ? `, cc ${m.cc}` : ""} <SlidersHorizontal size={11} />
          </button>
        </div>
        <time>
          {new Date(m.date).toLocaleString([], {
            month: "short",
            day: "numeric",
            year: "numeric",
            hour: "numeric",
            minute: "2-digit",
          })}
        </time>
        <Menu label="Message options" trigger={<MoreVertical size={18} />}>
          <MenuItem onSelect={() => showDetails("headers")}>
            Message details & headers
          </MenuItem>
          <MenuItem onSelect={() => showDetails("original")}>
            View original source
          </MenuItem>
        </Menu>
      </div>
      {m.remoteImages && (
        <div className="image-notice">
          Remote images are blocked for privacy.
          <button onClick={loadRemote}>Load images for this message</button>
        </div>
      )}
      {m.html ? (
        <iframe
          title="Email body"
          sandbox="allow-popups allow-popups-to-escape-sandbox"
          referrerPolicy="no-referrer"
          className="email-frame"
          srcDoc={m.html}
        />
      ) : (
        <pre className="plain-body">
          {m.plain ||
            "No readable message body. Check the attachments or original source."}
        </pre>
      )}
      {!!m.attachments.length && (
        <section className="attachments">
          <h2>
            Attachments <span>{m.attachments.length}</span>
          </h2>
          <div>
            {m.attachments.map((a) => (
              <a
                key={a.partId}
                className="attachment"
                href={`/api/messages/${m.id}/parts/${encodeURIComponent(a.partId || "root")}`}
                download
              >
                <FileText size={21} />
                <span>
                  <strong>{a.name}</strong>
                  <small>
                    {Math.max(1, Math.round(a.size / 1024))} KB
                    {a.inline ? " · Inline image" : ""}
                  </small>
                </span>
                <Paperclip size={14} />
              </a>
            ))}
          </div>
        </section>
      )}
      <div className="message-footer">
        Reading here keeps unread messages unread in Gmail.
      </div>
    </article>
  );
}
export default function App() {
  const [sidebar, setSidebar] = useState(true);
  const [views, setViews] = useState(loadViews);
  const [settings, setSettings] = useState(false);
  const [location, setLocation] = useState<Location>(() => ({
    ...loadViews()[0],
  }));
  const [input, setInput] = useState(() => expandQuery(location.query));
  const [pageToken, setPageToken] = useState("");
  const [history, setHistory] = useState<string[]>([]);
  const [status, setStatus] = useState<{
    connected: boolean;
    configured: boolean;
  } | null>(null);
  const [profile, setProfile] = useState("");
  const [labels, setLabels] = useState<Label[]>([]);
  const [page, setPage] = useState<Page>({
    messages: [],
    nextPage: null,
    unavailable: 0,
  });
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [refresh, setRefresh] = useState(0);
  const [opened, setOpened] = useState<string | null>(null);
  const [message, setMessage] = useState<Detail | null>(null);
  const [remote, setRemote] = useState(false);
  const [detailMode, setDetailMode] = useState<"headers" | "original" | null>(
    null,
  );
  const [original, setOriginal] = useState("");
  const search = useRef<HTMLInputElement>(null);
  const listRefresh = useRef(0);
  const messageRefresh = useRef(0);
  function fail(e: unknown) {
    if (e instanceof Error && e.name === "AbortError") return;
    setError(
      e instanceof Error ? e.message : "Something went wrong. Try again.",
    );
    if (e instanceof ApiError && e.code === "reconnect")
      setStatus((s) => (s ? { ...s, connected: false } : s));
  }
  useEffect(() => {
    const c = new AbortController();
    api<{ connected: boolean; configured: boolean }>("/api/status", c.signal)
      .then(setStatus)
      .catch(fail);
    const auth = new URLSearchParams(window.location.search).get("auth");
    if (auth) {
      setError(
        auth === "denied"
          ? "Google access was not approved. Connect again when you are ready."
          : "Google authorization could not be completed. Check the registered callback and reconnect.",
      );
      window.history.replaceState(null, "", "/");
    }
    return () => c.abort();
  }, [refresh]);
  useEffect(() => {
    if (!status?.connected) return;
    const c = new AbortController();
    Promise.all([
      api<{ emailAddress: string }>("/api/profile", c.signal).then((p) =>
        setProfile(p.emailAddress),
      ),
      api<{ labels: Label[] }>("/api/labels", c.signal).then((l) =>
        setLabels(l.labels),
      ),
    ]).catch(fail);
    return () => c.abort();
  }, [status?.connected, refresh]);
  useEffect(() => {
    if (!status?.connected || opened) return;
    const c = new AbortController();
    setLoading(true);
    setError("");
    setSelected(new Set());
    const params = new URLSearchParams({
      q: expandQuery(location.query),
      page: pageToken,
    });
    if (refresh !== listRefresh.current) params.set("refresh", "1");
    listRefresh.current = refresh;
    if (location.label) params.set("label", location.label);
    api<Page>(`/api/messages?${params}`, c.signal)
      .then(setPage)
      .catch(fail)
      .finally(() => {
        if (!c.signal.aborted) setLoading(false);
      });
    return () => c.abort();
  }, [status?.connected, location, pageToken, refresh, opened]);
  useEffect(() => {
    if (!opened || !status?.connected) return;
    const c = new AbortController();
    setLoading(true);
    setMessage(null);
    setError("");
    const forceRefresh = refresh !== messageRefresh.current;
    messageRefresh.current = refresh;
    api<Detail>(
      `/api/messages/${opened}?remote=${remote ? "1" : "0"}&refresh=${forceRefresh ? "1" : "0"}`,
      c.signal,
    )
      .then((m) =>
        setMessage({ ...m, remoteImages: remote ? false : m.remoteImages }),
      )
      .catch(fail)
      .finally(() => {
        if (!c.signal.aborted) setLoading(false);
      });
    return () => c.abort();
  }, [opened, status?.connected, remote, refresh]);
  useEffect(() => {
    if (detailMode !== "original" || !opened) return;
    const c = new AbortController();
    setOriginal("Loading original source…");
    fetch(`/api/messages/${opened}/original`, { signal: c.signal })
      .then(async (r) => {
        if (!r.ok) throw new Error("Original source could not be loaded.");
        return r.text();
      })
      .then(setOriginal)
      .catch((e) => {
        if (e.name !== "AbortError") setOriginal(e.message);
      });
    return () => c.abort();
  }, [detailMode, opened]);
  function navigate(l: Location) {
    setLocation(l);
    setInput(expandQuery(l.query));
    setOpened(null);
    setMessage(null);
    setPageToken("");
    setHistory([]);
    setSelected(new Set());
    setPage({ messages: [], nextPage: null, unavailable: 0 });
  }
  const starMatch = /^has:(yellow|red|green|blue|purple)-star$/.exec(
    location.query,
  );
  const starColor = starMatch ? colors[starMatch[1]] : undefined;
  const groups = new Map<string, Message[]>();
  page.messages.forEach((m) => {
    const key = dayName(m.date);
    groups.set(key, [...(groups.get(key) || []), m]);
  });
  return (
    <div className="app">
      <header className="app-header">
        <div className="header-actions">
          <IconButton
            label={sidebar ? "Collapse sidebar" : "Expand sidebar"}
            onClick={() => setSidebar(!sidebar)}
          >
            <MenuIcon size={22} />
          </IconButton>
          <a className="wordmark" href="/" aria-label="aMail home">
            a<span>Mail</span>
            <span className="brand-dot" />
          </a>
          <IconButton
            label="Refresh mail"
            disabled={!status?.connected || loading}
            onClick={() => setRefresh((x) => x + 1)}
            className={loading ? "refreshing" : ""}
          >
            <RefreshCw size={18} />
          </IconButton>
          <Menu label="Selection menu" trigger={<MoreVertical size={18} />}>
            <MenuItem
              disabled={!page.messages.length || !!opened || loading}
              onSelect={() =>
                setSelected(new Set(page.messages.map((m) => m.id)))
              }
            >
              Select all on this page
            </MenuItem>
            <MenuItem
              disabled={!page.messages.length || !!opened || loading}
              onSelect={() =>
                setSelected(
                  new Set(
                    page.messages
                      .filter((m) => m.labelIds.includes("UNREAD"))
                      .map((m) => m.id),
                  ),
                )
              }
            >
              Select unread
            </MenuItem>
            <MenuItem onSelect={() => setSelected(new Set())}>
              Clear selection
            </MenuItem>
          </Menu>
        </div>
        <form
          className="search"
          onSubmit={(e) => {
            e.preventDefault();
            if (input.trim()) {
              const query = input.trim();
              navigate({ name: "Search results", query });
              setInput(query);
            }
          }}
        >
          <Search size={19} />
          <input
            ref={search}
            aria-label="Search Gmail"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            placeholder="Search your mail"
          />
          <span className="search-hint">Gmail search</span>
          {input && (
            <button
              type="button"
              aria-label="Clear search"
              onClick={() => {
                setInput("");
                search.current?.focus();
              }}
            >
              <X size={16} />
            </button>
          )}
        </form>
        <div className="header-right">
          <span className="read-only-pill">
            <LockKeyhole size={12} />
            Read only
          </span>
          <Menu
            label="Profile and settings"
            trigger={
              <span className="profile-avatar">
                {profile ? profile[0].toUpperCase() : "A"}
              </span>
            }
          >
            <div className="profile-info">
              <strong>{profile || "aMail"}</strong>
              <small>Gmail · Read-only access</small>
            </div>
            <MenuItem onSelect={() => setSettings(true)}>
              <SettingsIcon size={15} />
              Saved searches & tabs
            </MenuItem>
            <MenuItem
              onSelect={() => {
                window.location.href = "/api/oauth/start";
              }}
            >
              <LogIn size={15} />
              {status?.connected ? "Reconnect Gmail" : "Connect Gmail"}
            </MenuItem>
          </Menu>
        </div>
      </header>
      <div className={`workspace ${sidebar ? "expanded" : "collapsed"}`}>
        <aside
          className="sidebar"
          aria-label="Mailbox navigation"
          inert={!sidebar}
        >
          <div className="sidebar-inner">
            <SidebarSection name="Mailbox">
              {folders.map((f) => (
                <button
                  key={f.name}
                  className={`nav-item ${location.query === f.query && !opened ? "active" : ""}`}
                  onClick={() => navigate(f)}
                >
                  <f.icon size={17} />
                  {f.name}
                </button>
              ))}
            </SidebarSection>
            <SidebarSection name="Views">
              {defaults.slice(1).map((v) => (
                <button
                  key={v.id}
                  className={`nav-item ${location.query === v.query && !opened ? "active" : ""}`}
                  onClick={() => navigate(v)}
                >
                  {colors[v.id] ? (
                    <Star
                      size={16}
                      fill="currentColor"
                      style={{ color: colors[v.id] }}
                    />
                  ) : v.id === "unread" ? (
                    <Mail size={17} />
                  ) : (
                    <Circle
                      size={v.id === "today" ? 9 : 8}
                      fill="currentColor"
                      className="view-dot"
                    />
                  )}
                  {v.name}
                </button>
              ))}
            </SidebarSection>
            <SidebarSection name="Labels">
              {labels
                .filter((l) => l.type === "user")
                .map((l) => (
                  <button
                    key={l.id}
                    className={`nav-item ${location.label === l.id ? "active" : ""}`}
                    onClick={() =>
                      navigate({
                        name: l.name,
                        query: `label:"${l.name.replaceAll("\\", "\\\\").replaceAll('"', '\\"')}"`,
                        label: l.id,
                      })
                    }
                  >
                    <Tag
                      size={16}
                      fill={l.color?.backgroundColor || "#dce1e7"}
                      color={l.color?.backgroundColor || "#a3acb8"}
                    />
                    <span>{l.name}</span>
                  </button>
                ))}
              {!labels.some((l) => l.type === "user") && (
                <p className="sidebar-empty">
                  {status?.connected
                    ? "No custom labels"
                    : "Connect to see your labels"}
                </p>
              )}
            </SidebarSection>
            <SidebarSection name="Bookmarks">
              {bookmarks.map((b) => (
                <button
                  className={`nav-item ${location.query === b.query ? "active" : ""}`}
                  key={b.name}
                  onClick={() => navigate(b)}
                >
                  <b.icon size={17} />
                  {b.name}
                </button>
              ))}
            </SidebarSection>
            <div className="sidebar-foot">
              <span className="status-dot" />
              {status?.connected ? "Connected to Gmail" : "Not connected"}
            </div>
          </div>
        </aside>
        <main>
          <nav className="tabs" aria-label="Saved searches">
            {views.map((v) => (
              <button
                key={v.id}
                className={location.id === v.id ? "active" : ""}
                onClick={() => navigate(v)}
              >
                {v.name}
              </button>
            ))}
            <button
              className="tabs-settings"
              aria-label="Configure tabs"
              onClick={() => setSettings(true)}
            >
              <SlidersHorizontal size={15} />
            </button>
          </nav>
          {error && (
            <div className="error-banner" role="alert">
              <AlertCircle size={17} />
              <span>{error}</span>
              <button onClick={() => setRefresh((x) => x + 1)}>Retry</button>
            </div>
          )}
          {!status ? (
            <div className="empty-state">Opening aMail…</div>
          ) : !status.connected ? (
            <section className="connect-state">
              <div className="connect-icon">
                <Inbox size={29} />
              </div>
              <p className="eyebrow">YOUR MAIL, A LITTLE QUIETER</p>
              <h1>A clear view of your inbox.</h1>
              <p>
                Connect Gmail to browse your latest messages,
                <br />
                find what matters, and read without distractions.
              </p>
              <Button
                disabled={!status.configured}
                onClick={() => {
                  window.location.href = "/api/oauth/start";
                }}
              >
                <LogIn size={17} />
                Connect Gmail
              </Button>
              <div className="connect-assurance">
                <LockKeyhole size={13} />
                <span>Read-only access. Your mail stays exactly as it is.</span>
              </div>
              {!status.configured && (
                <p className="error-text">
                  Set AMAIL_CLIENT_SECRET to your Google web client JSON, then
                  restart.
                </p>
              )}
              <div className="connect-features">
                <span>Mailbox-wide search</span>
                <span>Saved search tabs</span>
                <span>Private by default</span>
              </div>
            </section>
          ) : opened ? (
            loading ? (
              <div className="empty-state">Opening message…</div>
            ) : message ? (
              <MessageView
                m={message}
                labels={labels}
                back={() => setOpened(null)}
                showDetails={setDetailMode}
                loadRemote={() => setRemote(true)}
              />
            ) : (
              <div className="empty-state">
                <Button variant="outline" onClick={() => setOpened(null)}>
                  Back to messages
                </Button>
              </div>
            )
          ) : (
            <>
              <div className="list-meta">
                <span>
                  {selected.size
                    ? `${selected.size} selected on this page`
                    : location.name}
                  {location.name === "Search results" && (
                    <code>{location.query}</code>
                  )}
                </span>
                <span>
                  {loading
                    ? "Fetching from Gmail…"
                    : `${history.length * 100 + (page.messages.length ? 1 : 0)}–${history.length * 100 + page.messages.length}`}
                  <IconButton
                    label="Previous page"
                    disabled={!history.length || loading}
                    onClick={() => {
                      setPageToken(history[history.length - 1]);
                      setHistory(history.slice(0, -1));
                    }}
                  >
                    <ChevronLeft size={16} />
                  </IconButton>
                  <IconButton
                    label="Next page"
                    disabled={!page.nextPage || loading}
                    onClick={() => {
                      setHistory([...history, pageToken]);
                      setPageToken(page.nextPage!);
                    }}
                  >
                    <ChevronRight size={16} />
                  </IconButton>
                </span>
              </div>
              {loading ? (
                <div className="skeletons" aria-label="Loading messages">
                  {Array.from({ length: 14 }, (_, i) => (
                    <div key={i} className="skeleton-row">
                      <i />
                      <i />
                      <i />
                    </div>
                  ))}
                </div>
              ) : !page.messages.length ? (
                <div className="empty-state">
                  <Inbox size={30} />
                  <h2>No messages here</h2>
                  {starMatch ? (
                    <>
                      <p>
                        Gmail returned no matches for{" "}
                        <code>{location.query}</code>. Try this same search in
                        Gmail to compare, or show all starred mail.
                      </p>
                      <button
                        className="empty-action"
                        onClick={() =>
                          navigate({ name: "Starred", query: "is:starred" })
                        }
                      >
                        Show all starred mail
                      </button>
                    </>
                  ) : (
                    <p>Try another search or view.</p>
                  )}
                </div>
              ) : (
                <div className="mail-list">
                  {[...groups].map(([day, messages]) => (
                    <section key={day} aria-label={day}>
                      <div className="day-heading">
                        <h2>{day}</h2>
                        <span>{messages.length}</span>
                      </div>
                      {messages.map((m) => (
                        <MailRow
                          key={m.id}
                          m={m}
                          labels={labels}
                          starColor={starColor}
                          selected={selected.has(m.id)}
                          toggle={() =>
                            setSelected((prev) => {
                              const n = new Set(prev);
                              if (n.has(m.id)) n.delete(m.id);
                              else n.add(m.id);
                              return n;
                            })
                          }
                          open={() => {
                            setOpened(m.id);
                            setRemote(false);
                          }}
                        />
                      ))}
                    </section>
                  ))}
                </div>
              )}
              {!loading && (
                <footer className="list-footer">
                  <span>
                    Latest 100 matches per page · Search runs across Gmail
                  </span>
                  <span>
                    {page.unavailable
                      ? `${page.unavailable} messages no longer available`
                      : "Nothing is marked read"}
                  </span>
                </footer>
              )}
            </>
          )}
        </main>
      </div>
      {settings && (
        <Settings
          views={views}
          close={() => setSettings(false)}
          save={(v) => {
            localStorage.setItem("amail.views.v1", JSON.stringify(v));
            setViews(v);
            if (location.id)
              navigate(v.find((x) => x.id === location.id) || v[0]);
          }}
        />
      )}
      {detailMode && message && (
        <Modal
          title={
            detailMode === "headers" ? "Message details" : "Original message"
          }
          description={
            detailMode === "headers"
              ? "Full headers returned by Gmail for this message."
              : "Read-only RFC 2822 source fetched directly from Gmail."
          }
          open
          onClose={() => setDetailMode(null)}
        >
          {detailMode === "headers" ? (
            <dl className="headers">
              {message.headers.map((h, i) => (
                <div key={i}>
                  <dt>{h.name}</dt>
                  <dd>{h.value}</dd>
                </div>
              ))}
            </dl>
          ) : (
            <pre className="original-source">{original}</pre>
          )}
        </Modal>
      )}
    </div>
  );
}
