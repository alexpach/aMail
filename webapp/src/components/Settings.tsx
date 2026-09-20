import { useState } from "react";
import { ArrowUp, ArrowDown, Plus, Trash2 } from "lucide-react";
import { type SavedView, defaults } from "../types";
import { Button } from "./spectrum/button";
import { IconButton, Modal } from "./controls";
export function Settings({
  views,
  save,
  close,
}: {
  views: SavedView[];
  save: (v: SavedView[]) => void;
  close: () => void;
}) {
  const [draft, setDraft] = useState(views);
  const [error, setError] = useState("");
  function move(i: number, delta: number) {
    const next = [...draft];
    [next[i], next[i + delta]] = [next[i + delta], next[i]];
    setDraft(next);
  }
  return (
    <Modal
      title="Saved searches"
      description="Make your mailbox feel like yours. Tabs and their order are saved in this browser."
      open
      onClose={close}
    >
      <div className="settings-note">
        Queries use Gmail search syntax. <code>{"{today}"}</code> means midnight
        in your local timezone. Primary is your normal inbox. Investors is an
        editable label query.
      </div>
      <div className="view-editor">
        {draft.map((v, i) => (
          <div className="view-edit" key={v.id}>
            <input
              aria-label={`Tab ${i + 1} name`}
              value={v.name}
              maxLength={24}
              placeholder="Tab name"
              onChange={(e) =>
                setDraft(
                  draft.map((x) =>
                    x.id === v.id ? { ...x, name: e.target.value } : x,
                  ),
                )
              }
            />
            <input
              aria-label={`Tab ${i + 1} query`}
              value={v.query}
              maxLength={2000}
              placeholder="in:inbox is:unread"
              onChange={(e) =>
                setDraft(
                  draft.map((x) =>
                    x.id === v.id ? { ...x, query: e.target.value } : x,
                  ),
                )
              }
            />
            <IconButton
              label={`Move ${v.name} up`}
              disabled={i === 0}
              onClick={() => move(i, -1)}
            >
              <ArrowUp />
            </IconButton>
            <IconButton
              label={`Move ${v.name} down`}
              disabled={i === draft.length - 1}
              onClick={() => move(i, 1)}
            >
              <ArrowDown />
            </IconButton>
            <IconButton
              label={`Remove ${v.name}`}
              disabled={draft.length === 1}
              onClick={() => setDraft(draft.filter((x) => x.id !== v.id))}
            >
              <Trash2 />
            </IconButton>
          </div>
        ))}
      </div>
      <Button
        variant="outline"
        disabled={draft.length >= 30}
        onClick={() =>
          setDraft([
            ...draft,
            { id: crypto.randomUUID(), name: "New view", query: "in:inbox" },
          ])
        }
      >
        <Plus />
        Add tab
      </Button>
      <p className="settings-note">
        Gmail does not return star colors in message data. Color tabs use
        Gmail’s <code>has:blue-star</code> search operators. General lists show
        neutral stars. Color results still need verification with your account.
      </p>
      {error && (
        <p role="alert" className="error-text">
          {error}
        </p>
      )}
      <div className="modal-footer">
        <Button variant="ghost" onClick={() => setDraft(defaults)}>
          Restore defaults
        </Button>
        <Button
          onClick={() => {
            if (draft.some((v) => !v.name.trim() || !v.query.trim()))
              return setError("Every tab needs a name and a Gmail query.");
            try {
              save(
                draft.map((v) => ({
                  ...v,
                  name: v.name.trim(),
                  query: v.query.trim(),
                })),
              );
              close();
            } catch {
              setError(
                "This browser could not save settings. Check local storage permissions.",
              );
            }
          }}
        >
          Save changes
        </Button>
      </div>
    </Modal>
  );
}
