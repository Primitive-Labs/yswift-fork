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
}

/// Attempts to convert an EntryChange to YrsEntryChange.
/// Returns None if the change involves nested shared types (YMap, YArray, YText, YDoc, etc.)
/// which should be accessed via dedicated methods instead.
pub fn try_from_entry_change(key: &str, item: &EntryChange) -> Option<YrsMapChange> {
    let change = match item {
        EntryChange::Inserted(value) => match value {
            Out::Any(val) => {
                let mut buf = String::new();
                val.to_json(&mut buf);
                YrsEntryChange::Inserted { value: buf }
            }
            // Skip nested shared types - they should be accessed via dedicated methods
            Out::YMap(_)
            | Out::YArray(_)
            | Out::YText(_)
            | Out::YXmlElement(_)
            | Out::YXmlFragment(_)
            | Out::YXmlText(_)
            | Out::YDoc(_)
            | Out::UndefinedRef(_) => return None,
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
                // Skip nested shared types
                return None;
            }
        }
        EntryChange::Removed(value) => {
            if let Out::Any(val) = value {
                let mut buf = String::new();
                val.to_json(&mut buf);
                YrsEntryChange::Removed { value: buf }
            } else {
                // Skip nested shared types
                return None;
            }
        }
    };
    Some(YrsMapChange {
        key: key.to_string(),
        change,
    })
}
