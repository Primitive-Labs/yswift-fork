use crate::attrs::YrsAttrs;
use crate::delta::YrsDelta;
use crate::subscription::YSubscription;
use crate::transaction::YrsTransaction;
use yrs::Any;
use parking_lot::ReentrantMutex;
use std::cell::UnsafeCell;
use std::fmt::Debug;
use std::sync::Arc;
use yrs::{GetString, Observable, Text, TextRef};
use yrs::branch::Branch;
use crate::doc::YrsCollectionPtr;

pub(crate) struct YrsText(ReentrantMutex<UnsafeCell<TextRef>>);

// Safe because ReentrantMutex provides proper thread synchronization.
unsafe impl Send for YrsText {}
unsafe impl Sync for YrsText {}

/// A guard that holds the lock and provides access to the inner TextRef.
pub(crate) struct TextRefGuard<'a> {
    _guard: parking_lot::ReentrantMutexGuard<'a, UnsafeCell<TextRef>>,
    ptr: *mut TextRef,
}

impl<'a> TextRefGuard<'a> {
    pub(crate) fn as_ref(&self) -> &TextRef {
        unsafe { &*self.ptr }
    }

    pub(crate) fn as_mut(&mut self) -> &mut TextRef {
        unsafe { &mut *self.ptr }
    }
}

impl YrsText {
    fn inner(&self) -> TextRefGuard<'_> {
        let guard = self.0.lock();
        let ptr = unsafe { (*self.0.data_ptr()).get() };
        TextRefGuard { _guard: guard, ptr }
    }
}

impl AsRef<Branch> for YrsText {
    fn as_ref(&self) -> &Branch {
        //FIXME: after yrs v0.18 use logical references
        let guard = self.inner();
        let branch_ref: &Branch = guard.as_ref().as_ref();
        unsafe { std::mem::transmute::<&Branch, &Branch>(branch_ref) }
    }
}

impl From<TextRef> for YrsText {
    fn from(value: TextRef) -> Self {
        YrsText(ReentrantMutex::new(UnsafeCell::new(value)))
    }
}

pub(crate) trait YrsTextObservationDelegate: Send + Sync + Debug {
    fn call(&self, value: Vec<YrsDelta>);
}

impl YrsText {
    pub(crate) fn raw_ptr(&self) -> YrsCollectionPtr {
        let guard = self.inner();
        YrsCollectionPtr::from(guard.as_ref().as_ref())
    }

    pub(crate) fn format(
        &self,
        transaction: &YrsTransaction,
        index: u32,
        length: u32,
        attrs: String,
    ) {
        let mut tx = transaction.transaction();
        let tx = tx.as_mut().unwrap();

        let a = YrsAttrs::from(attrs);

        self.inner().as_mut().format(tx, index, length, a.0)
    }

    pub(crate) fn append(&self, tx: &YrsTransaction, text: String) {
        let mut tx = tx.transaction();
        let tx = tx.as_mut().unwrap();

        self.inner().as_mut().push(tx, text.as_str());
    }

    pub(crate) fn insert(&self, tx: &YrsTransaction, index: u32, chunk: String) {
        let mut tx = tx.transaction();
        let tx = tx.as_mut().unwrap();

        self.inner().as_mut().insert(tx, index, chunk.as_str())
    }

    pub(crate) fn insert_with_attributes(
        &self,
        transaction: &YrsTransaction,
        index: u32,
        chunk: String,
        attrs: String,
    ) {
        let mut tx = transaction.transaction();
        let tx = tx.as_mut().unwrap();

        let a = YrsAttrs::from(attrs);

        self.inner()
            .as_mut()
            .insert_with_attributes(tx, index, chunk.as_str(), a.0)
    }

    pub(crate) fn insert_embed(&self, transaction: &YrsTransaction, index: u32, content: String) {
        let mut tx = transaction.transaction();
        let tx = tx.as_mut().unwrap();

        let avalue = Any::from_json(content.as_str()).unwrap();

        self.inner().as_mut().insert_embed(tx, index, avalue);
    }

    pub(crate) fn insert_embed_with_attributes(
        &self,
        transaction: &YrsTransaction,
        index: u32,
        content: String,
        attrs: String,
    ) {
        let mut tx = transaction.transaction();
        let tx = tx.as_mut().unwrap();

        let avalue = Any::from_json(content.as_str()).unwrap();

        let a = YrsAttrs::from(attrs);

        self.inner()
            .as_mut()
            .insert_embed_with_attributes(tx, index, avalue, a.0);
    }

    pub(crate) fn get_string(&self, tx: &YrsTransaction) -> String {
        let mut tx = tx.transaction();
        let tx = tx.as_mut().unwrap();

        self.inner().as_ref().get_string(tx)
    }

    pub(crate) fn remove_range(&self, transaction: &YrsTransaction, start: u32, length: u32) {
        let mut tx = transaction.transaction();
        let tx = tx.as_mut().unwrap();

        self.inner().as_mut().remove_range(tx, start, length)
    }

    pub(crate) fn length(&self, transaction: &YrsTransaction) -> u32 {
        let tx = transaction.transaction();
        let tx = tx.as_ref().unwrap();

        self.inner().as_ref().len(tx)
    }

    pub(crate) fn observe(&self, delegate: Box<dyn YrsTextObservationDelegate>) -> Arc<YSubscription> {
        let mut text = self.inner();
        let subscription = text
            .as_mut()
            .observe(move |transaction, text_event| {
                let delta = text_event.delta(transaction);
                let result: Vec<YrsDelta> =
                    delta.iter().map(|change| YrsDelta::from(change)).collect();
                delegate.call(result)
            });

            Arc::new(YSubscription::new(subscription))
    }

    /// Applies a delta to the text. Delta is a JSON array of operations.
    pub(crate) fn apply_delta(&self, transaction: &YrsTransaction, delta: Vec<YrsDelta>) {
        use yrs::types::Delta;
        let mut tx = transaction.transaction();
        let tx = tx.as_mut().unwrap();

        let deltas: Vec<Delta<Any>> = delta.into_iter().map(|d| {
            match d {
                YrsDelta::Inserted { value, attrs } => {
                    let any_value = Any::from_json(value.as_str()).unwrap();
                    let attrs_parsed = if attrs.is_empty() {
                        None
                    } else {
                        Some(Box::new(YrsAttrs::from(attrs).0))
                    };
                    Delta::Inserted(any_value, attrs_parsed)
                }
                YrsDelta::Deleted { index } => Delta::Deleted(index),
                YrsDelta::Retained { index, attrs } => {
                    let attrs_parsed = if attrs.is_empty() {
                        None
                    } else {
                        Some(Box::new(YrsAttrs::from(attrs).0))
                    };
                    Delta::Retain(index, attrs_parsed)
                }
            }
        }).collect();

        self.inner().as_mut().apply_delta(tx, deltas);
    }

    /// Returns the text content as a list of diff chunks with formatting.
    pub(crate) fn diff(&self, transaction: &YrsTransaction) -> Vec<YrsDiff> {
        use yrs::types::text::Diff;
        let tx = transaction.transaction();
        let tx = tx.as_ref().unwrap();

        let diffs: Vec<Diff<()>> = self.inner().as_ref().diff(tx, |_| ());
        diffs.into_iter().map(|d| YrsDiff::from(&d)).collect()
    }
}

/// Represents a diff chunk from YText.
pub(crate) enum YrsDiff {
    Text { value: String, attrs: String },
    Embed { value: String, attrs: String },
    Other { attrs: String },
}

impl From<&yrs::types::text::Diff<()>> for YrsDiff {
    fn from(diff: &yrs::types::text::Diff<()>) -> Self {
        use yrs::Out;
        let attrs = diff.attributes.as_ref()
            .map(|a| YrsAttrs::from(*a.clone()).into())
            .unwrap_or_default();

        match &diff.insert {
            Out::Any(any) => {
                let mut buf = String::new();
                any.to_json(&mut buf);
                YrsDiff::Text { value: buf, attrs }
            }
            _ => YrsDiff::Other { attrs }
        }
    }
}
