use crate::array::YrsArray;
use crate::doc::{YrsCollectionPtr, YrsDoc};
use crate::error::CodingError;
use crate::mapchange::{try_from_entry_change, YrsMapChange};
use crate::subscription::YSubscription;
use crate::text::YrsText;
use crate::transaction::YrsTransaction;
use parking_lot::ReentrantMutex;
use std::cell::UnsafeCell;
use std::fmt::Debug;
use std::sync::Arc;
use yrs::branch::Branch;
use yrs::{Any, Map, MapRef, Observable, Out};

pub(crate) struct YrsMap(ReentrantMutex<UnsafeCell<MapRef>>);

// Marks that this type can be transferred across thread boundaries.
// Safe because ReentrantMutex provides proper thread synchronization.
unsafe impl Send for YrsMap {}
// Marks that this type is safe to share references between threads.
// Safe because ReentrantMutex provides proper thread synchronization.
unsafe impl Sync for YrsMap {}

/// A guard that holds the lock and provides access to the inner MapRef.
pub(crate) struct MapRefGuard<'a> {
    _guard: parking_lot::ReentrantMutexGuard<'a, UnsafeCell<MapRef>>,
    ptr: *mut MapRef,
}

impl<'a> MapRefGuard<'a> {
    pub(crate) fn as_ref(&self) -> &MapRef {
        unsafe { &*self.ptr }
    }

    pub(crate) fn as_mut(&mut self) -> &mut MapRef {
        unsafe { &mut *self.ptr }
    }
}

impl YrsMap {
    fn inner(&self) -> MapRefGuard<'_> {
        let guard = self.0.lock();
        let ptr = unsafe { (*self.0.data_ptr()).get() };
        MapRefGuard { _guard: guard, ptr }
    }
}

impl AsRef<Branch> for YrsMap {
    fn as_ref(&self) -> &Branch {
        //FIXME: after yrs v0.18 use logical references
        let guard = self.inner();
        let branch = guard.as_ref();
        unsafe { std::mem::transmute(branch.as_ref()) }
    }
}

// Provides the implementation for the From trait, supporting
// converting from a MapRef type into a YrsMap type.
impl From<MapRef> for YrsMap {
    fn from(value: MapRef) -> Self {
        YrsMap(ReentrantMutex::new(UnsafeCell::new(value)))
    }
}

// A representation of a callback that is invoked from the various
// map iterators, specifically to provide the JSON-string of the iterated
// value from the map (for example, with `values` or `iter`).
//
// This allows the outside code (Swift, for example) to
// handle the deserialization from JSON string into whatever the appropriate
// type is within the swift language bindings. The `keys` iterator doesn't
// need this "translation", while `values` does.
//
// The type is boxed and used as a dynamic type:
// `Box<dyn YrsMapIteratorDelegate>`
// rather than having the keys, values, or iter functions expose an iterator
// back to the external language bindings.
pub(crate) trait YrsMapIteratorDelegate: Send + Sync + Debug {
    fn call(&self, value: String);
}

pub(crate) trait YrsMapKVIteratorDelegate: Send + Sync + Debug {
    fn call(&self, key: String, value: String);
}

pub(crate) trait YrsMapObservationDelegate: Send + Sync + Debug {
    fn call(&self, value: Vec<YrsMapChange>);
}

/*
IMPL order:
- [X] [insert, len, contains_key]
- [X] [get, remove, clear]
- [X] [keys, values, iter]
- [ ] [observe, unobserve]
 */

impl YrsMap {
    pub(crate) fn raw_ptr(&self) -> YrsCollectionPtr {
        let guard = self.inner();
        YrsCollectionPtr::from(guard.as_ref().as_ref())
    }

    /// Inserts the key and value you provide into the map.
    pub(crate) fn insert(&self, transaction: &YrsTransaction, key: String, value: String) {
        // decodes the `value` as JSON and converts it into a lib0::Any enumeration
        let any_value = Any::from_json(value.as_str()).unwrap();

        // acquire a *mutable* transaction
        let mut binding = transaction.transaction();
        let tx = binding.as_mut().unwrap();

        // pull out a mutable reference to the YrsMap this type wraps
        let mut map = self.inner();
        // insert into the wrapped map.
        map.as_mut().insert(tx, key, any_value);

        // Documentation note from YrsMap about inserting a preliminary type - for future
        // reference...
        // // insert nested shared type
        // let nested = map.insert(&mut txn, "key2", MapPrelim::from([("inner", "value2")]));
        // nested.insert(&mut txn, "inner2", 100);
    }

    /// Returns the size of the map.
    pub(crate) fn length(&self, transaction: &YrsTransaction) -> u32 {
        let map = self.inner();
        // acquire a transaction, but we don't need to borrow it since we're
        // not mutating anything in this method.
        let binding = transaction.transaction();
        let tx = binding.as_ref().unwrap();
        // If we try and do the above on a single line, I get the error:
        // creates a temporary value which is freed while still in use

        map.as_ref().len(tx)
    }

    /// Returns a Boolean value that indicates whether the map contains the key you provide.
    pub(crate) fn contains_key(&self, transaction: &YrsTransaction, key: String) -> bool {
        let map = self.inner();
        // acquire a transaction, but we don't need to borrow it since we're
        // not mutating anything in this method.
        let tx = transaction.transaction();
        let tx = tx.as_ref().unwrap();

        map.as_ref().contains_key(tx, key.as_str())
    }

    pub(crate) fn get(
        &self,
        transaction: &YrsTransaction,
        key: String,
    ) -> Result<String, CodingError> {
        let binding = transaction.transaction();
        let tx = binding.as_ref().unwrap();
        let map = self.inner();
        match map.as_ref().get(tx, key.as_str()) {
            Some(Out::Any(any)) => {
                let mut buf = String::new();
                any.to_json(&mut buf);
                Ok(buf)
            }
            Some(_) => Err(CodingError::EncodingError),
            None => Err(CodingError::DecodingError),
        }
    }

    pub(crate) fn remove(
        &self,
        transaction: &YrsTransaction,
        key: String,
    ) -> Result<Option<String>, CodingError> {
        // acquire a *mutable* transaction
        let mut binding = transaction.transaction();
        let tx = binding.as_mut().unwrap();

        // get a mutable reference to the YrsMap this type wraps
        let mut map = self.inner();

        let optional_value = map.as_mut().remove(tx, key.as_str());
        match optional_value {
            // there was some kind of value in the map, try to cast it and convert
            // to JSON
            Some(v) => {
                if let Out::Any(any) = v {
                    let mut buf = String::new();
                    any.to_json(&mut buf);
                    return Ok(Some(buf));
                } else {
                    return Err(CodingError::EncodingError);
                }
            }
            // No value returned from the map on remove, so return the Optional
            // string as None.
            None => {
                return Ok(None);
            }
        }
    }

    pub(crate) fn clear(&self, transaction: &YrsTransaction) {
        // acquire a *mutable* transaction
        let mut binding = transaction.transaction();
        let tx = binding.as_mut().unwrap();

        // get a mutable reference to the YrsMap this type wraps
        let mut map = self.inner();

        map.as_mut().clear(tx);
    }

    pub(crate) fn keys(
        &self,
        transaction: &YrsTransaction,
        delegate: Box<dyn YrsMapIteratorDelegate>,
    ) {
        // The internal `keys` function in Rust returns an explicit iterator that you can
        // fiddle with.
        //
        // fn keys<'a, T: ReadTxn + 'a>(&'a self, txn: &'a T) -> Keys<'a, &'a T, T>
        //
        // For these language bindings we're instead holding onto the iterator
        // ourselves, and expecting a delegate type from the language binding side that
        // we call with each value as it is available.

        // get a mutable transaction
        let binding = transaction.transaction();
        let txn = binding.as_ref().unwrap();

        let map = self.inner();
        map.as_ref().keys(txn).for_each(|key_value| {
            delegate.call(key_value.to_string());
        });
    }

    pub(crate) fn values(
        &self,
        transaction: &YrsTransaction,
        delegate: Box<dyn YrsMapIteratorDelegate>,
    ) {
        // Like the `keys` iterator pattern, we're holding onto the Rust iterator
        // ourselves, and expecting a delegate type from the language binding side that
        // we call with each value as it is available.

        // get a mutable transaction
        let binding = transaction.transaction();
        let txn = binding.as_ref().unwrap();

        let map = self.inner();
        let iterator = map.as_ref().values(txn);
        iterator.for_each(|value_list| {
            // value is being returned as Vec<Value> from YrsMap - unclear
            // why, but maybe we iterate over each element and attempt to any.to_json on it?
            // 20mar2023 - checking w/ Bartosz on if I'm missing something about
            // the values iterator here.
            //
            // The upstream yrs value iterator goes into the Yrs internal type
            // `Item`, which can potentially contain a list of values within it.
            // In practice, it appears to contains a single value for this usage of it.
            value_list.iter().for_each(|val_in_list| {
                // Only call delegate for JSON-serializable values (Out::Any).
                // Skip nested shared types (YMap, YArray, YText, YDoc, etc.) -
                // these should be accessed via dedicated get_map/get_array/get_text methods.
                if let Out::Any(any) = val_in_list {
                    let mut buf = String::new();
                    any.to_json(&mut buf);
                    delegate.call(buf);
                }
                // Silently skip non-Any values (nested shared types)
            });
        });
    }

    pub(crate) fn each(
        &self,
        transaction: &YrsTransaction,
        delegate: Box<dyn YrsMapKVIteratorDelegate>,
    ) {
        // Like the `keys` and `values` iterator pattern, we're holding onto the Rust iterator
        // ourselves, and expecting a delegate type from the language binding side that
        // we call with each value as it is available.

        // get a mutable transaction
        let binding = transaction.transaction();
        let txn = binding.as_ref().unwrap();

        let map = self.inner();
        let iterator = map.as_ref().iter(txn);
        iterator.for_each(|key_value_pair| {
            // key_value_pair is being returned as a tuple of (&str, Value)
            // we'll pass the key value (String) straight through to the delegate,
            // but do the extra work to convert Value to a JSON string for decoding
            // on the far side of the language binding - or at least try to.
            //
            // Only call delegate for JSON-serializable values (Out::Any).
            // Skip nested shared types (YMap, YArray, YText, YDoc, etc.) -
            // these should be accessed via dedicated get_map/get_array/get_text methods.
            if let Out::Any(any) = key_value_pair.1 {
                let mut buf = String::new();
                any.to_json(&mut buf);
                delegate.call(key_value_pair.0.to_string(), buf);
            }
            // Silently skip non-Any values (nested shared types)
        });
    }

    pub(crate) fn observe(&self, delegate: Box<dyn YrsMapObservationDelegate>) -> Arc<YSubscription> {
        let mut map = self.inner();
        let subscription = map
            .as_mut()
            .observe(move |transaction, map_event| {
                let delta = map_event.keys(transaction);
                // Filter out nested shared types (YMap, YArray, YText, YDoc) which return None
                let result: Vec<YrsMapChange> = delta
                    .iter()
                    .filter_map(|val| try_from_entry_change(val.0, val.1))
                    .collect();
                delegate.call(result)
            });

            Arc::new(YSubscription::new(subscription))
    }

    // MARK: - Subdoc methods

    /// Gets a subdocument for the specified key.
    /// Returns None if the key doesn't exist or the value is not a document.
    pub(crate) fn get_doc(
        &self,
        transaction: &YrsTransaction,
        key: String,
    ) -> Option<Arc<YrsDoc>> {
        let binding = transaction.transaction();
        let tx = binding.as_ref().unwrap();
        let map = self.inner();

        if let Some(Out::YDoc(doc)) = map.as_ref().get(tx, key.as_str()) {
            Some(Arc::new(YrsDoc::from_doc(doc)))
        } else {
            None
        }
    }

    /// Inserts a subdocument with the specified key.
    /// Returns a reference to the integrated subdocument.
    pub(crate) fn insert_doc(
        &self,
        transaction: &YrsTransaction,
        key: String,
        doc: &YrsDoc,
    ) -> Arc<YrsDoc> {
        let mut binding = transaction.transaction();
        let tx = binding.as_mut().unwrap();
        let mut map = self.inner();

        // Clone the inner Doc and insert it
        let inner_doc = doc.inner().clone();
        let inserted = map.as_mut().insert(tx, key, inner_doc);
        Arc::new(YrsDoc::from_doc(inserted))
    }

    // MARK: - Nested shared type methods

    /// Gets a nested YMap for the specified key.
    /// Returns None if the key doesn't exist or the value is not a map.
    pub(crate) fn get_map(
        &self,
        transaction: &YrsTransaction,
        key: String,
    ) -> Option<Arc<YrsMap>> {
        let binding = transaction.transaction();
        let tx = binding.as_ref().unwrap();
        let map = self.inner();

        if let Some(Out::YMap(nested)) = map.as_ref().get(tx, key.as_str()) {
            Some(Arc::new(YrsMap::from(nested)))
        } else {
            None
        }
    }

    /// Gets a nested YArray for the specified key.
    /// Returns None if the key doesn't exist or the value is not an array.
    pub(crate) fn get_array(
        &self,
        transaction: &YrsTransaction,
        key: String,
    ) -> Option<Arc<YrsArray>> {
        let binding = transaction.transaction();
        let tx = binding.as_ref().unwrap();
        let map = self.inner();

        if let Some(Out::YArray(nested)) = map.as_ref().get(tx, key.as_str()) {
            Some(Arc::new(YrsArray::from(nested)))
        } else {
            None
        }
    }

    /// Gets a nested YText for the specified key.
    /// Returns None if the key doesn't exist or the value is not text.
    pub(crate) fn get_text(
        &self,
        transaction: &YrsTransaction,
        key: String,
    ) -> Option<Arc<YrsText>> {
        let binding = transaction.transaction();
        let tx = binding.as_ref().unwrap();
        let map = self.inner();

        if let Some(Out::YText(nested)) = map.as_ref().get(tx, key.as_str()) {
            Some(Arc::new(YrsText::from(nested)))
        } else {
            None
        }
    }

    /// Checks if the value at the specified key is an undefined reference.
    /// Returns true if the key exists but holds an undefined/deleted reference.
    pub(crate) fn is_undefined(
        &self,
        transaction: &YrsTransaction,
        key: String,
    ) -> bool {
        let binding = transaction.transaction();
        let tx = binding.as_ref().unwrap();
        let map = self.inner();

        matches!(map.as_ref().get(tx, key.as_str()), Some(Out::UndefinedRef(_)))
    }

    /// Inserts an empty nested YMap at the specified key.
    /// Returns a reference to the inserted map.
    pub(crate) fn insert_map(
        &self,
        transaction: &YrsTransaction,
        key: String,
    ) -> Arc<YrsMap> {
        use yrs::MapPrelim;

        let mut binding = transaction.transaction();
        let tx = binding.as_mut().unwrap();
        let mut map = self.inner();

        let prelim: MapPrelim = Default::default();
        let nested: MapRef = map.as_mut().insert(tx, key, prelim);
        Arc::new(YrsMap::from(nested))
    }

    /// Inserts an empty nested YArray at the specified key.
    /// Returns a reference to the inserted array.
    pub(crate) fn insert_array(
        &self,
        transaction: &YrsTransaction,
        key: String,
    ) -> Arc<YrsArray> {
        use yrs::{ArrayPrelim, ArrayRef};

        let mut binding = transaction.transaction();
        let tx = binding.as_mut().unwrap();
        let mut map = self.inner();

        let nested: ArrayRef = map.as_mut().insert(tx, key, ArrayPrelim::default());
        Arc::new(YrsArray::from(nested))
    }

    /// Inserts an empty nested YText at the specified key.
    /// Returns a reference to the inserted text.
    pub(crate) fn insert_text(
        &self,
        transaction: &YrsTransaction,
        key: String,
    ) -> Arc<YrsText> {
        use yrs::{TextPrelim, TextRef};

        let mut binding = transaction.transaction();
        let tx = binding.as_mut().unwrap();
        let mut map = self.inner();

        let nested: TextRef = map.as_mut().insert(tx, key, TextPrelim::new(""));
        Arc::new(YrsText::from(nested))
    }

    /// Updates value only if different from current. Returns true if updated.
    pub(crate) fn try_update(
        &self,
        transaction: &YrsTransaction,
        key: String,
        value: String,
    ) -> bool {
        use yrs::Map;
        let any_value = Any::from_json(value.as_str()).unwrap();
        let mut binding = transaction.transaction();
        let tx = binding.as_mut().unwrap();
        let mut map = self.inner();
        map.as_mut().try_update(tx, key, any_value)
    }

    /// Gets existing nested map or creates new one at key.
    pub(crate) fn get_or_insert_map(
        &self,
        transaction: &YrsTransaction,
        key: String,
    ) -> Arc<YrsMap> {
        use yrs::Map;
        let mut binding = transaction.transaction();
        let tx = binding.as_mut().unwrap();
        let mut map = self.inner();
        let nested: MapRef = map.as_mut().get_or_init(tx, key.as_str());
        Arc::new(YrsMap::from(nested))
    }

    /// Gets existing nested array or creates new one at key.
    pub(crate) fn get_or_insert_array(
        &self,
        transaction: &YrsTransaction,
        key: String,
    ) -> Arc<YrsArray> {
        use yrs::{ArrayRef, Map};
        let mut binding = transaction.transaction();
        let tx = binding.as_mut().unwrap();
        let mut map = self.inner();
        let nested: ArrayRef = map.as_mut().get_or_init(tx, key.as_str());
        Arc::new(YrsArray::from(nested))
    }

    /// Gets existing nested text or creates new one at key.
    pub(crate) fn get_or_insert_text(
        &self,
        transaction: &YrsTransaction,
        key: String,
    ) -> Arc<YrsText> {
        use yrs::{Map, TextRef};
        let mut binding = transaction.transaction();
        let tx = binding.as_mut().unwrap();
        let mut map = self.inner();
        let nested: TextRef = map.as_mut().get_or_init(tx, key.as_str());
        Arc::new(YrsText::from(nested))
    }
}

#[cfg(test)]
mod tests {
    use crate::YrsDoc;

    #[test]
    fn verify_new_map_has_zero_count() {
        let doc = YrsDoc::new();
        let map = doc.get_map("example_map".to_string());

        let txn = doc.transact(None);
        assert_eq!(map.length(&txn), 0);
    }

    #[test]
    fn map_insert_and_count() {
        let doc = YrsDoc::new();
        let map = doc.get_map("example_map".to_string());

        let key_to_insert = "AB123".to_string();
        let value_to_insert = "\"Hello\"".to_string();

        let txn = doc.transact(None);

        assert_eq!(map.contains_key(&txn, key_to_insert.clone()), false);

        map.insert(&txn, key_to_insert.clone(), value_to_insert);
        assert_eq!(map.length(&txn), 1);

        assert_eq!(map.contains_key(&txn, key_to_insert), true);
    }

    #[test]
    fn map_insert_and_get() {
        let doc = YrsDoc::new();
        let map = doc.get_map("example_map".to_string());

        let key_to_insert = "AB123".to_string();
        let value_to_insert = "\"Hello\"".to_string();

        let txn = doc.transact(None);

        assert_eq!(map.contains_key(&txn, key_to_insert.clone()), false);

        map.insert(&txn, key_to_insert.clone(), value_to_insert.clone());
        assert_eq!(map.length(&txn), 1);

        let result = map.get(&txn, key_to_insert.clone()).unwrap();
        assert_eq!(result, value_to_insert);
    }

    #[test]
    fn map_remove() {
        let doc = YrsDoc::new();
        let map = doc.get_map("example_map".to_string());

        let key_to_insert = "AB123".to_string();
        let value_to_insert = "\"Hello\"".to_string();

        let txn = doc.transact(None);

        assert_eq!(map.contains_key(&txn, key_to_insert.clone()), false);

        map.insert(&txn, key_to_insert.clone(), value_to_insert.clone());

        let returned = map.remove(&txn, key_to_insert.clone());
        let unwrapped_return = returned.unwrap();
        assert_eq!(unwrapped_return, Some(value_to_insert.clone()));
        assert_eq!(map.length(&txn), 0);
    }

    #[test]
    fn map_clear() {
        let doc = YrsDoc::new();
        let map = doc.get_map("example_map".to_string());

        let key_to_insert = "AB123".to_string();
        let value_to_insert = "\"Hello\"".to_string();

        let txn = doc.transact(None);

        map.insert(&txn, key_to_insert.clone(), value_to_insert.clone());
        assert_eq!(map.length(&txn), 1);

        map.clear(&txn);
        assert_eq!(map.length(&txn), 0);
    }

    /*
        ## The section below is Joe trying to sort out the pieces to make a unit test
        that "works" the code structure when you invoke "keys" - which involves multiple
        calls to a delegate object that you need to provide. I haven't been able to figure
        out how to structure the dyn Box<T> object and get it implementing the required
        trait on the Rust side of things: `crate::map::YrsMapIteratorDelegate`

        I'll work/test the pattern through the Swift language side of this binding setup,
        but I'd really like to understand how to get it working on the Rust side as well.
        For now, however, I'll just leave this at where I got to - and hope to come back to
        resolve it in the future with some more experience Rust brains alongside.

        #[derive(Debug)]
        struct KeyDelegate {
            collected: Vec<String>
        }
        // Marks that this type can be transferred across thread boundaries.
        //unsafe impl Send for RefCell<KeyDelegate> {}
        // Marks that this type is safe to share references between threads.
        unsafe impl Sync for KeyDelegate {}

        impl KeyDelegate {

            fn append(&mut self, value: String) {
                &self.collected.push(value);
            }

            fn new() -> KeyDelegate {
                let newDelegate = KeyDelegate {
                    collected: Vec::<String>::new()
                };
                return newDelegate
            }

            // fn test(&self) -> Box<dyn crate::map::YrsMapIteratorDelegate> {
            //     return Box::new(self)
            // }
        }

        impl crate::map::YrsMapIteratorDelegate for Box<KeyDelegate> {
            fn call(&self, key_value: String) {
                self.append(key_value)
            }
        }

        // impl crate::map::YrsMapIteratorDelegate for KeyDelegate {
        //     fn call(&self, key_value: String) {

        //     }
        // }

        #[test]
        fn map_keys() {
            let doc = YrsDoc::new();
            let map = doc.get_map("example_map".to_string());

            let first_key_to_insert = "AB123".to_string();
            let second_key_to_insert = "890YZ".to_string();
            let value_to_insert = "\"Hello\"".to_string();

            let txn = doc.transact();

            map.insert(&txn, first_key_to_insert.clone(), value_to_insert.clone());
            map.insert(&txn, second_key_to_insert.clone(), value_to_insert.clone());
            assert_eq!(map.length(&txn), 2);

            let delegate = Box::new(KeyDelegate::new());
            map.keys(&txn, delegate);
    //                     ^^^^^^^^ the trait `YrsMapIteratorDelegate` is not implemented for `KeyDelegate`
    //                     Compiler error when invoking `cargo test`
            assert_eq!(delegate.collected.len(), 2);
        }

     */
}
