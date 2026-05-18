use yrs::types::EntryChange;
use yrs::Out;

pub struct YrsMapChange {
    pub key: String,
    pub change: YrsEntryChange,
}

pub enum YrsEntryChange {
    Inserted {
        value: String,
    },
    Updated {
        old_value: String,
        new_value: String,
    },
    Removed {
        value: String,
    },
    /// A nested shared type (YMap / YArray / YText / YDoc / ...)
    /// was inserted at this key. The value isn't a serializable
    /// scalar — callers who need the contents should re-read the
    /// map via its typed accessor (`get_map`, `get_array`, etc.).
    /// The `kind` tag identifies which shared-type slot was used.
    InsertedNested {
        kind: String,
    },
    /// A nested shared type was replaced by another value (scalar
    /// or nested). Carries both old and new type tags so callers
    /// can decide whether to unwind references.
    UpdatedNested {
        old_kind: String,
        new_kind: String,
    },
    /// A nested shared type was removed from this key.
    RemovedNested {
        kind: String,
    },
}

/// Convert an EntryChange to YrsMapChange.
///
/// Scalar (`Out::Any`) values produce the Inserted/Updated/Removed
/// variants with a serialized JSON value. Nested shared types
/// (`Out::YMap`, `Out::YArray`, `Out::YText`, `Out::YDoc`, etc.)
/// produce the `*Nested` variants — the event includes a `kind`
/// string identifying which shared-type slot was used, but does
/// NOT include the shared-type contents. Callers that need the
/// contents must re-read them via the typed accessor.
///
/// Returns `Some` for every change — nothing is silently dropped.
/// Previously this filtered out nested-type changes, which hid
/// record add/remove events on model-root maps from observers.
pub fn try_from_entry_change(key: &str, item: &EntryChange) -> Option<YrsMapChange> {
    let change = match item {
        EntryChange::Inserted(value) => match value {
            Out::Any(val) => {
                let mut buf = String::new();
                val.to_json(&mut buf);
                YrsEntryChange::Inserted { value: buf }
            }
            other => YrsEntryChange::InsertedNested {
                kind: shared_kind(other).to_string(),
            },
        },
        EntryChange::Updated(old_value, new_value) => {
            if let (Out::Any(old), Out::Any(new)) = (old_value, new_value) {
                let mut old_string = String::new();
                let mut new_string = String::new();
                old.to_json(&mut old_string);
                new.to_json(&mut new_string);
                YrsEntryChange::Updated {
                    old_value: old_string,
                    new_value: new_string,
                }
            } else {
                YrsEntryChange::UpdatedNested {
                    old_kind: shared_kind(old_value).to_string(),
                    new_kind: shared_kind(new_value).to_string(),
                }
            }
        }
        EntryChange::Removed(value) => {
            if let Out::Any(val) = value {
                let mut buf = String::new();
                val.to_json(&mut buf);
                YrsEntryChange::Removed { value: buf }
            } else {
                YrsEntryChange::RemovedNested {
                    kind: shared_kind(value).to_string(),
                }
            }
        }
    };
    Some(YrsMapChange {
        key: key.to_string(),
        change,
    })
}

/// Describes which `Out` variant a value is, as a short tag for
/// the `*Nested` entry-change events. Scalar (`Any`) values never
/// reach this — those take the `Inserted/Updated/Removed` paths.
fn shared_kind(out: &Out) -> &'static str {
    match out {
        Out::Any(_) => "any",
        Out::YMap(_) => "ymap",
        Out::YArray(_) => "yarray",
        Out::YText(_) => "ytext",
        Out::YXmlElement(_) => "yxmlelement",
        Out::YXmlFragment(_) => "yxmlfragment",
        Out::YXmlText(_) => "yxmltext",
        Out::YDoc(_) => "ydoc",
        Out::UndefinedRef(_) => "undefined",
        _ => "unknown",
    }
}
