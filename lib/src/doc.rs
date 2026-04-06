use crate::array::YrsArray;
use crate::error::CodingError;
use crate::map::YrsMap;
use crate::subdoc::{YrsDestroyObservationDelegate, YrsDocOptions, YrsSubdocsEvent, YrsSubdocsObservationDelegate, YrsUpdateEvent, YrsUpdateObservationDelegate};
use crate::subscription::YSubscription;
use crate::text::YrsText;
use crate::transaction::YrsTransaction;
use crate::undo::YrsUndoManager;
use crate::UniffiCustomTypeConverter;
use parking_lot::ReentrantMutex;
use std::cell::UnsafeCell;
use std::sync::Arc;
use std::borrow::Borrow;
use yrs::branch::Branch;
use yrs::{updates::decoder::Decode, ArrayRef, Doc, MapRef, OffsetKind, Options, Origin, ReadTxn, StateVector, Transact};

pub(crate) struct YrsDoc(ReentrantMutex<UnsafeCell<Doc>>);

// Safe because ReentrantMutex provides proper thread synchronization.
unsafe impl Send for YrsDoc {}
unsafe impl Sync for YrsDoc {}

/// A guard that holds the lock and provides access to the inner Doc.
pub(crate) struct DocGuard<'a> {
    _guard: parking_lot::ReentrantMutexGuard<'a, UnsafeCell<Doc>>,
    ptr: *mut Doc,
}

impl<'a> DocGuard<'a> {
    pub(crate) fn as_ref(&self) -> &Doc {
        unsafe { &*self.ptr }
    }

    #[allow(dead_code)]
    pub(crate) fn as_mut(&mut self) -> &mut Doc {
        unsafe { &mut *self.ptr }
    }
}

impl YrsDoc {
    fn doc(&self) -> DocGuard<'_> {
        let guard = self.0.lock();
        let ptr = unsafe { (*self.0.data_ptr()).get() };
        DocGuard { _guard: guard, ptr }
    }

    pub(crate) fn new() -> Self {
        let mut options = Options::default();
        options.offset_kind = OffsetKind::Utf16;
        let doc = yrs::Doc::with_options(options);

        Self(ReentrantMutex::new(UnsafeCell::new(doc)))
    }

    pub(crate) fn encode_diff_v1(
        &self,
        transaction: &YrsTransaction,
        state_vector: Vec<u8>,
    ) -> Result<Vec<u8>, CodingError> {
        let mut tx = transaction.transaction();
        let tx = tx.as_mut().unwrap();

        StateVector::decode_v1(state_vector.borrow())
            .map_err(|_e| CodingError::DecodingError)
            .map(|sv| tx.encode_diff_v1(&sv))
    }

    pub(crate) fn get_text(&self, name: String) -> Arc<YrsText> {
        let text_ref = self.doc().as_ref().get_or_insert_text(name.as_str());
        Arc::from(YrsText::from(text_ref))
    }

    pub(crate) fn get_array(&self, name: String) -> Arc<YrsArray> {
        let array_ref: ArrayRef = self.doc().as_ref().get_or_insert_array(name.as_str()).into();
        Arc::from(YrsArray::from(array_ref))
    }

    pub(crate) fn get_map(&self, name: String) -> Arc<YrsMap> {
        let map_ref: MapRef = self.doc().as_ref().get_or_insert_map(name.as_str()).into();
        Arc::from(YrsMap::from(map_ref))
    }

    pub(crate) fn transact<'doc>(&self, origin: Option<YrsOrigin>) -> Arc<YrsTransaction> {
        let doc = self.doc();
        let tx = if let Some(origin) = origin {
            doc.as_ref().transact_mut_with(origin)
        } else {
            doc.as_ref().transact_mut()
        };
        Arc::from(YrsTransaction::from(tx))
    }

    pub(crate) fn undo_manager(&self, tracked_refs: Vec<YrsCollectionPtr>) -> Arc<YrsUndoManager> {
        let doc = self.doc();
        let mut i = tracked_refs.into_iter();
        let first = i.next().unwrap();
        let mut undo_manager = yrs::undo::UndoManager::new(doc.as_ref(), &first);
        while let Some(n) = i.next() {
            undo_manager.expand_scope(&n);
        }
        Arc::new(YrsUndoManager::from(undo_manager))
    }

    // MARK: - Subdoc methods

    /// Returns whether auto_load is enabled for this document.
    pub(crate) fn auto_load(&self) -> bool {
        self.doc().as_ref().auto_load()
    }

    /// Returns the client ID for this document.
    pub(crate) fn client_id(&self) -> u64 {
        self.doc().as_ref().client_id()
    }

    /// Destroys this subdocument within the parent transaction.
    pub(crate) fn destroy(&self, parent_txn: &YrsTransaction) {
        let mut tx = parent_txn.transaction();
        if let Some(tx) = tx.as_mut() {
            self.doc().as_ref().destroy(tx);
        }
    }

    /// Returns the globally unique identifier for this document.
    pub(crate) fn guid(&self) -> String {
        self.doc().as_ref().guid().to_string()
    }

    /// Requests the parent to load this subdocument's data.
    pub(crate) fn load(&self, parent_txn: &YrsTransaction) {
        let mut tx = parent_txn.transaction();
        if let Some(tx) = tx.as_mut() {
            self.doc().as_ref().load(tx);
        }
    }

    /// Creates a new document with the specified options.
    pub(crate) fn new_with_options(options: YrsDocOptions) -> Self {
        let mut opts = Options::default();
        opts.auto_load = options.auto_load;
        if let Some(client_id) = options.client_id {
            opts.client_id = client_id;
        }
        if let Some(guid) = options.guid {
            opts.guid = Arc::from(guid.as_str());
        }
        opts.offset_kind = OffsetKind::Utf16;
        opts.should_load = options.should_load;

        Self(ReentrantMutex::new(UnsafeCell::new(Doc::with_options(opts))))
    }

    /// Observes when this document is destroyed.
    pub(crate) fn observe_destroy(
        &self,
        delegate: Box<dyn YrsDestroyObservationDelegate>,
    ) -> Arc<YSubscription> {
        let doc = self.doc();
        let subscription = doc
            .as_ref()
            .observe_destroy(move |_txn, _doc| {
                delegate.call();
            })
            .expect("Failed to observe destroy");

        Arc::new(YSubscription::new(subscription))
    }

    /// Observes subdocument lifecycle changes (added, loaded, removed).
    pub(crate) fn observe_subdocs(
        &self,
        delegate: Box<dyn YrsSubdocsObservationDelegate>,
    ) -> Arc<YSubscription> {
        let doc = self.doc();
        let subscription = doc
            .as_ref()
            .observe_subdocs(move |_txn, event| {
                let added: Vec<Arc<YrsDoc>> = event
                    .added()
                    .map(|d| Arc::new(YrsDoc::from_doc(d.clone())))
                    .collect();
                let loaded: Vec<Arc<YrsDoc>> = event
                    .loaded()
                    .map(|d| Arc::new(YrsDoc::from_doc(d.clone())))
                    .collect();
                let removed: Vec<Arc<YrsDoc>> = event
                    .removed()
                    .map(|d| Arc::new(YrsDoc::from_doc(d.clone())))
                    .collect();
                delegate.call(YrsSubdocsEvent {
                    added,
                    loaded,
                    removed,
                });
            })
            .expect("Failed to observe subdocs");

        Arc::new(YSubscription::new(subscription))
    }

    /// Observes document update events. The delegate receives the raw update
    /// bytes after each transaction, equivalent to JS `doc.on("update", ...)`.
    pub(crate) fn observe_update_v1(
        &self,
        delegate: Box<dyn YrsUpdateObservationDelegate>,
    ) -> Arc<YSubscription> {
        let doc = self.doc();
        let subscription = doc
            .as_ref()
            .observe_update_v1(move |_txn, event| {
                delegate.call(YrsUpdateEvent {
                    update: event.update.to_vec(),
                });
            })
            .expect("Failed to observe update");

        Arc::new(YSubscription::new(subscription))
    }

    /// Returns the parent document if this is a subdocument.
    pub(crate) fn parent_doc(&self) -> Option<Arc<YrsDoc>> {
        self.doc()
            .as_ref()
            .parent_doc()
            .map(|doc| Arc::new(YrsDoc::from_doc(doc)))
    }

    /// Checks if two documents are the same instance (reference equality).
    pub(crate) fn ptr_eq(&self, other: &YrsDoc) -> bool {
        Doc::ptr_eq(self.doc().as_ref(), other.doc().as_ref())
    }

    /// Returns whether this document should be loaded/synced.
    pub(crate) fn should_load(&self) -> bool {
        self.doc().as_ref().should_load()
    }
}

impl YrsDoc {
    /// Creates a YrsDoc from an existing yrs Doc.
    pub(crate) fn from_doc(doc: Doc) -> Self {
        Self(ReentrantMutex::new(UnsafeCell::new(doc)))
    }

    /// Returns a clone of the inner Doc for internal use.
    pub(crate) fn inner(&self) -> Doc {
        self.doc().as_ref().clone()
    }
}

#[derive(Clone)]
pub(crate) struct YrsOrigin(Arc<[u8]>);

impl From<Origin> for YrsOrigin {
    fn from(value: Origin) -> Self {
        YrsOrigin(Arc::from(value.as_ref()))
    }
}

impl Into<Origin> for YrsOrigin {
    fn into(self) -> Origin {
        Origin::from(self.0.as_ref())
    }
}

impl UniffiCustomTypeConverter for YrsOrigin {
    type Builtin = Vec<u8>;

    fn into_custom(val: Self::Builtin) -> uniffi::Result<Self> where Self: Sized {
        Ok(YrsOrigin(val.into()))
    }

    fn from_custom(obj: Self) -> Self::Builtin {
        obj.0.to_vec()
    }
}

#[derive(Copy, Clone)]
#[repr(transparent)]
pub(crate) struct YrsCollectionPtr(*const Branch);

unsafe impl Send for YrsCollectionPtr { }
unsafe impl Sync for YrsCollectionPtr { }

impl AsRef<Branch> for YrsCollectionPtr {
    #[inline]
    fn as_ref(&self) -> &Branch {
        unsafe { self.0.as_ref() }.unwrap()
    }
}

impl<'a> From<&'a Branch> for YrsCollectionPtr {
    #[inline]
    fn from(value: &'a Branch) -> Self {
        let ptr = value as *const Branch;
        YrsCollectionPtr(ptr)
    }
}

impl UniffiCustomTypeConverter for YrsCollectionPtr {
    type Builtin = u64;

    fn into_custom(val: Self::Builtin) -> uniffi::Result<Self> where Self: Sized {
        let ptr = val as usize as *const Branch;
        Ok(YrsCollectionPtr(ptr))
    }

    fn from_custom(obj: Self) -> Self::Builtin {
        obj.0 as usize as u64
    }
}
