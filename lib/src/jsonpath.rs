use yrs::json_path::{JsonPath, JsonPathEval};
use yrs::{Array, GetString, Map, Out};

use crate::transaction::YrsTransaction;

/// Error that can occur when parsing or executing a JSON path query.
#[derive(Debug, thiserror::Error)]
pub enum YrsJsonPathError {
    #[error("Invalid JSON path: {message}")]
    ParseError { message: String },
}

impl YrsTransaction {
    /// Execute a JSON path query against the document.
    ///
    /// # Arguments
    /// * `path` - A JSON path expression (e.g., "$.users[*].name")
    ///
    /// # Returns
    /// A vector of JSON-encoded results matching the path expression.
    ///
    /// # Errors
    /// Returns an error if the path expression is invalid.
    pub(crate) fn json_path(&self, path: String) -> Result<Vec<String>, YrsJsonPathError> {
        let parsed = JsonPath::parse(&path).map_err(|e| YrsJsonPathError::ParseError {
            message: e.to_string(),
        })?;

        let tx = self.transaction();
        let tx = tx.as_ref().unwrap();

        let results: Vec<String> = tx
            .json_path(&parsed)
            .map(|out| {
                let mut buf = String::new();
                match out {
                    Out::Any(any) => {
                        any.to_json(&mut buf);
                    }
                    Out::YArray(arr) => {
                        // Serialize array contents as JSON array
                        buf.push('[');
                        let mut first = true;
                        for item in arr.iter(tx) {
                            if !first {
                                buf.push(',');
                            }
                            first = false;
                            if let Out::Any(any) = item {
                                any.to_json(&mut buf);
                            } else {
                                buf.push_str("null");
                            }
                        }
                        buf.push(']');
                    }
                    Out::YMap(map) => {
                        // Serialize map contents as JSON object
                        buf.push('{');
                        let mut first = true;
                        for (key, value) in map.iter(tx) {
                            if !first {
                                buf.push(',');
                            }
                            first = false;
                            buf.push('"');
                            buf.push_str(&key);
                            buf.push_str("\":");
                            if let Out::Any(any) = value {
                                any.to_json(&mut buf);
                            } else {
                                buf.push_str("null");
                            }
                        }
                        buf.push('}');
                    }
                    Out::YText(text) => {
                        // Serialize text as JSON string
                        let s = text.get_string(tx);
                        buf.push('"');
                        // Simple escape for JSON string
                        for c in s.chars() {
                            match c {
                                '"' => buf.push_str("\\\""),
                                '\\' => buf.push_str("\\\\"),
                                '\n' => buf.push_str("\\n"),
                                '\r' => buf.push_str("\\r"),
                                '\t' => buf.push_str("\\t"),
                                c => buf.push(c),
                            }
                        }
                        buf.push('"');
                    }
                    Out::YDoc(_) => {
                        buf.push_str("null");
                    }
                    Out::YXmlElement(_) | Out::YXmlFragment(_) | Out::YXmlText(_) => {
                        buf.push_str("null");
                    }
                    Out::UndefinedRef(_) => {
                        buf.push_str("null");
                    }
                }
                buf
            })
            .collect();

        Ok(results)
    }
}
