use std::fmt::Debug;
use std::sync::Arc;

use crate::doc::YrsDoc;

/// Options for creating a YrsDoc with specific configuration.
#[derive(Debug)]
pub(crate) struct YrsDocOptions {
    pub auto_load: bool,
    pub client_id: Option<u64>,
    pub guid: Option<String>,
    pub should_load: bool,
}

/// Event emitted when subdocuments are added, loaded, or removed.
pub(crate) struct YrsSubdocsEvent {
    pub added: Vec<Arc<YrsDoc>>,
    pub loaded: Vec<Arc<YrsDoc>>,
    pub removed: Vec<Arc<YrsDoc>>,
}

/// Delegate for observing subdocument lifecycle changes.
pub(crate) trait YrsSubdocsObservationDelegate: Send + Sync + Debug {
    fn call(&self, event: YrsSubdocsEvent);
}

/// Delegate for observing document destruction.
pub(crate) trait YrsDestroyObservationDelegate: Send + Sync + Debug {
    fn call(&self);
}

/// Event emitted when the document receives an update.
pub(crate) struct YrsUpdateEvent {
    pub update: Vec<u8>,
}

/// Delegate for observing document updates.
pub(crate) trait YrsUpdateObservationDelegate: Send + Sync + Debug {
    fn call(&self, event: YrsUpdateEvent);
}
