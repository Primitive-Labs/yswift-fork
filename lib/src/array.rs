use crate::doc::{YrsCollectionPtr, YrsDoc};
use crate::map::YrsMap;
use crate::subscription::YSubscription;
use crate::text::YrsText;
use crate::transaction::YrsTransaction;
use crate::{change::YrsChange, error::CodingError};
use parking_lot::ReentrantMutex;
use std::cell::UnsafeCell;
use std::fmt::Debug;
use std::sync::Arc;
use yrs::branch::Branch;
use yrs::{Any, Array, ArrayRef, Observable, Out};

pub(crate) struct YrsArray(ReentrantMutex<UnsafeCell<ArrayRef>>);

// Safe because ReentrantMutex provides proper thread synchronization.
unsafe impl Send for YrsArray {}
unsafe impl Sync for YrsArray {}

/// A guard that holds the lock and provides access to the inner ArrayRef.
pub(crate) struct ArrayRefGuard<'a> {
    _guard: parking_lot::ReentrantMutexGuard<'a, UnsafeCell<ArrayRef>>,
    ptr: *mut ArrayRef,
}

impl<'a> ArrayRefGuard<'a> {
    pub(crate) fn as_ref(&self) -> &ArrayRef {
        unsafe { &*self.ptr }
    }

    pub(crate) fn as_mut(&mut self) -> &mut ArrayRef {
        unsafe { &mut *self.ptr }
    }
}

impl YrsArray {
    fn inner(&self) -> ArrayRefGuard<'_> {
        let guard = self.0.lock();
        let ptr = unsafe { (*self.0.data_ptr()).get() };
        ArrayRefGuard { _guard: guard, ptr }
    }
}

impl AsRef<Branch> for YrsArray {
    fn as_ref(&self) -> &Branch {
        //FIXME: after yrs v0.18 use logical references
        let guard = self.inner();
        let branch = guard.as_ref();
        unsafe { std::mem::transmute(branch.as_ref()) }
    }
}

impl From<ArrayRef> for YrsArray {
    fn from(value: ArrayRef) -> Self {
        YrsArray(ReentrantMutex::new(UnsafeCell::new(value)))
    }
}

pub(crate) trait YrsArrayEachDelegate: Send + Sync + Debug {
    fn call(&self, value: String);
}

pub(crate) trait YrsArrayObservationDelegate: Send + Sync + Debug {
    fn call(&self, value: Vec<YrsChange>);
}

impl YrsArray {
    pub(crate) fn raw_ptr(&self) -> YrsCollectionPtr {
        let guard = self.inner();
        YrsCollectionPtr::from(guard.as_ref().as_ref())
    }

    pub(crate) fn each(
        &self,
        transaction: &YrsTransaction,
        delegate: Box<dyn YrsArrayEachDelegate>,
    ) {
        let tx = transaction.transaction();
        let tx = tx.as_ref().unwrap();

        let arr = self.inner();
        arr.as_ref().iter(tx).for_each(|val| {
            let mut buf = String::new();
            if let Out::Any(any) = val {
                any.to_json(&mut buf);
                delegate.call(buf);
            } else {
                // @TODO: fix silly handling, it will just call with empty string if casting fails
                delegate.call(buf);
            }
        });
    }

    pub(crate) fn get(
        &self,
        transaction: &YrsTransaction,
        index: u32,
    ) -> Result<String, CodingError> {
        let tx = transaction.transaction();
        let tx = tx.as_ref().unwrap();
        let arr = self.inner();
        if let Some(value) = arr.as_ref().get(tx, index) {
            let mut buf = String::new();
            if let Out::Any(any) = value {
                any.to_json(&mut buf);
                Ok(buf)
            } else {
                Err(CodingError::EncodingError)
            }
        } else {
            // Actually there is no element here, so it shouldn't be EncodingErro
            Err(CodingError::EncodingError)
        }
    }

    pub(crate) fn insert(&self, transaction: &YrsTransaction, index: u32, value: String) {
        let avalue = Any::from_json(value.as_str()).unwrap();

        let mut tx = transaction.transaction();
        let tx = tx.as_mut().unwrap();

        let mut arr = self.inner();
        arr.as_mut().insert(tx, index, avalue);
    }

    pub(crate) fn insert_range(
        &self,
        transaction: &YrsTransaction,
        index: u32,
        values: Vec<String>,
    ) {
        let mut arr = self.inner();
        let mut tx = transaction.transaction();
        let tx = tx.as_mut().unwrap();

        let add_values: Vec<Any> = values
            .into_iter()
            .map(|value| Any::from_json(value.as_str()).unwrap())
            .collect();

        arr.as_mut().insert_range(tx, index, add_values)
    }

    pub(crate) fn length(&self, transaction: &YrsTransaction) -> u32 {
        let arr = self.inner();
        let tx = transaction.transaction();
        let tx = tx.as_ref().unwrap();

        arr.as_ref().len(tx)
    }

    pub(crate) fn push_back(&self, transaction: &YrsTransaction, value: String) {
        let avalue = Any::from_json(value.as_str()).unwrap();
        let mut tx = transaction.transaction();
        let tx = tx.as_mut().unwrap();

        self.inner().as_mut().push_back(tx, avalue);
    }

    pub(crate) fn push_front(&self, transaction: &YrsTransaction, value: String) {
        let avalue = Any::from_json(value.as_str()).unwrap();

        let mut tx = transaction.transaction();
        let tx = tx.as_mut().unwrap();

        let mut arr = self.inner();
        arr.as_mut().push_front(tx, avalue);
    }

    pub(crate) fn remove(&self, transaction: &YrsTransaction, index: u32) {
        let mut tx = transaction.transaction();
        let tx = tx.as_mut().unwrap();

        let mut arr = self.inner();
        arr.as_mut().remove(tx, index)
    }

    pub(crate) fn remove_range(&self, transaction: &YrsTransaction, index: u32, len: u32) {
        let mut tx = transaction.transaction();
        let tx = tx.as_mut().unwrap();

        let mut arr = self.inner();
        arr.as_mut().remove_range(tx, index, len)
    }

    pub(crate) fn observe(&self, delegate: Box<dyn YrsArrayObservationDelegate>) -> Arc<YSubscription> {
        let mut arr = self.inner();
        let subscription = arr
            .as_mut()
            .observe(move |transaction, text_event| {
                let delta = text_event.delta(transaction);
                let result: Vec<YrsChange> =
                    delta.iter().map(|change| YrsChange::from(change)).collect();
                delegate.call(result)
            });

            Arc::new(YSubscription::new(subscription))
    }

    pub(crate) fn to_a(&self, transaction: &YrsTransaction) -> Vec<String> {
        let arr = self.inner();
        let tx = transaction.transaction();
        let tx = tx.as_ref().unwrap();

        let arr = arr.as_ref()
            .iter(tx)
            .filter_map(|v| {
                let mut buf = String::new();
                if let Out::Any(any) = v {
                    any.to_json(&mut buf);
                    Some(buf)
                } else {
                    None
                }
            })
            .collect::<Vec<String>>();

        arr
    }

    // MARK: - Subdoc methods

    /// Gets a subdocument at the specified index.
    /// Returns None if the index is out of bounds or the value is not a document.
    pub(crate) fn get_doc(
        &self,
        transaction: &YrsTransaction,
        index: u32,
    ) -> Option<Arc<YrsDoc>> {
        let tx = transaction.transaction();
        let tx = tx.as_ref().unwrap();
        let arr = self.inner();

        if let Some(Out::YDoc(doc)) = arr.as_ref().get(tx, index) {
            Some(Arc::new(YrsDoc::from_doc(doc)))
        } else {
            None
        }
    }

    /// Inserts a subdocument at the specified index.
    /// Returns a reference to the integrated subdocument.
    pub(crate) fn insert_doc(
        &self,
        transaction: &YrsTransaction,
        index: u32,
        doc: &YrsDoc,
    ) -> Arc<YrsDoc> {
        let mut tx = transaction.transaction();
        let tx = tx.as_mut().unwrap();
        let mut arr = self.inner();

        // Clone the inner Doc and insert it
        let inner_doc = doc.inner().clone();
        let inserted = arr.as_mut().insert(tx, index, inner_doc);
        Arc::new(YrsDoc::from_doc(inserted))
    }

    // MARK: - Nested shared type methods

    /// Gets a nested YMap at the specified index.
    pub(crate) fn get_map(&self, transaction: &YrsTransaction, index: u32) -> Option<Arc<YrsMap>> {
        let tx = transaction.transaction();
        let tx = tx.as_ref().unwrap();
        let arr = self.inner();
        if let Some(Out::YMap(nested)) = arr.as_ref().get(tx, index) {
            Some(Arc::new(YrsMap::from(nested)))
        } else {
            None
        }
    }

    /// Gets a nested YArray at the specified index.
    pub(crate) fn get_array(&self, transaction: &YrsTransaction, index: u32) -> Option<Arc<YrsArray>> {
        let tx = transaction.transaction();
        let tx = tx.as_ref().unwrap();
        let arr = self.inner();
        if let Some(Out::YArray(nested)) = arr.as_ref().get(tx, index) {
            Some(Arc::new(YrsArray::from(nested)))
        } else {
            None
        }
    }

    /// Gets a nested YText at the specified index.
    pub(crate) fn get_text(&self, transaction: &YrsTransaction, index: u32) -> Option<Arc<YrsText>> {
        let tx = transaction.transaction();
        let tx = tx.as_ref().unwrap();
        let arr = self.inner();
        if let Some(Out::YText(nested)) = arr.as_ref().get(tx, index) {
            Some(Arc::new(YrsText::from(nested)))
        } else {
            None
        }
    }

    /// Checks if value at index is an undefined reference.
    pub(crate) fn is_undefined(&self, transaction: &YrsTransaction, index: u32) -> bool {
        let tx = transaction.transaction();
        let tx = tx.as_ref().unwrap();
        let arr = self.inner();
        matches!(arr.as_ref().get(tx, index), Some(Out::UndefinedRef(_)))
    }

    /// Inserts an empty nested YMap at the specified index.
    pub(crate) fn insert_map(&self, transaction: &YrsTransaction, index: u32) -> Arc<YrsMap> {
        use yrs::{MapPrelim, MapRef};
        let mut tx = transaction.transaction();
        let tx = tx.as_mut().unwrap();
        let mut arr = self.inner();
        let prelim: MapPrelim = Default::default();
        let nested: MapRef = arr.as_mut().insert(tx, index, prelim);
        Arc::new(YrsMap::from(nested))
    }

    /// Inserts an empty nested YArray at the specified index.
    pub(crate) fn insert_array(&self, transaction: &YrsTransaction, index: u32) -> Arc<YrsArray> {
        use yrs::ArrayPrelim;
        let mut tx = transaction.transaction();
        let tx = tx.as_mut().unwrap();
        let mut arr = self.inner();
        let nested: ArrayRef = arr.as_mut().insert(tx, index, ArrayPrelim::default());
        Arc::new(YrsArray::from(nested))
    }

    /// Inserts an empty nested YText at the specified index.
    pub(crate) fn insert_text(&self, transaction: &YrsTransaction, index: u32) -> Arc<YrsText> {
        use yrs::{TextPrelim, TextRef};
        let mut tx = transaction.transaction();
        let tx = tx.as_mut().unwrap();
        let mut arr = self.inner();
        let nested: TextRef = arr.as_mut().insert(tx, index, TextPrelim::new(""));
        Arc::new(YrsText::from(nested))
    }

    /// Pushes an empty nested YMap to the end.
    pub(crate) fn push_map(&self, transaction: &YrsTransaction) -> Arc<YrsMap> {
        use yrs::{MapPrelim, MapRef};
        let mut tx = transaction.transaction();
        let tx = tx.as_mut().unwrap();
        let mut arr = self.inner();
        let prelim: MapPrelim = Default::default();
        let nested: MapRef = arr.as_mut().push_back(tx, prelim);
        Arc::new(YrsMap::from(nested))
    }

    /// Pushes an empty nested YArray to the end.
    pub(crate) fn push_array(&self, transaction: &YrsTransaction) -> Arc<YrsArray> {
        use yrs::ArrayPrelim;
        let mut tx = transaction.transaction();
        let tx = tx.as_mut().unwrap();
        let mut arr = self.inner();
        let nested: ArrayRef = arr.as_mut().push_back(tx, ArrayPrelim::default());
        Arc::new(YrsArray::from(nested))
    }

    /// Pushes an empty nested YText to the end.
    pub(crate) fn push_text(&self, transaction: &YrsTransaction) -> Arc<YrsText> {
        use yrs::{TextPrelim, TextRef};
        let mut tx = transaction.transaction();
        let tx = tx.as_mut().unwrap();
        let mut arr = self.inner();
        let nested: TextRef = arr.as_mut().push_back(tx, TextPrelim::new(""));
        Arc::new(YrsText::from(nested))
    }

    /// Moves element from source index to target index.
    pub(crate) fn move_to(&self, transaction: &YrsTransaction, source: u32, target: u32) {
        let mut tx = transaction.transaction();
        let tx = tx.as_mut().unwrap();
        let mut arr = self.inner();
        arr.as_mut().move_to(tx, source, target);
    }

    /// Moves range of elements to target index.
    pub(crate) fn move_range_to(
        &self,
        transaction: &YrsTransaction,
        start: u32,
        end: u32,
        target: u32,
    ) {
        use yrs::Assoc;
        let mut tx = transaction.transaction();
        let tx = tx.as_mut().unwrap();
        let mut arr = self.inner();
        arr.as_mut().move_range_to(tx, start, Assoc::After, end, Assoc::Before, target);
    }
}
