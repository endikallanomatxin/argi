OwnedHashSetIterator#(.key: Type, .policy: Type: HashPolicy#(policy, key)): Type = (
    ._entries : HashMapBorrowIterator#(.key: key, .value: _HashSetValue, .policy: policy)
)

implement#(.key: Type, .policy: Type: HashPolicy#(policy, key)) ReferenceIterable#(
    OwnedHashSet#(.key: key, .policy: policy)
) (
    .Item         : Type = key
    .IteratorType : Type = OwnedHashSetIterator#(.key: key, .policy: policy)

    .to_reference_iterator = (.value: &OwnedHashSet#(.key: key, .policy: policy)) -> (
        .iterator : OwnedHashSetIterator#(.key: key, .policy: policy)
    ) { iterator = (._entries = to_iterator(.value = &value&._map).iterator) }
)

implement#(.key: Type, .policy: Type: HashPolicy#(policy, key)) Iterator#(
    OwnedHashSetIterator#(.key: key, .policy: policy)
) (
    .Item : Type = &key

    .has_next = (.self: &OwnedHashSetIterator#(.key: key, .policy: policy)) -> (.ok: Bool) {
        ok = has_next(&self&._entries).ok
    }

    .next = (.self: $&OwnedHashSetIterator#(.key: key, .policy: policy)) -> (.value: &key) {
        value = next($&self&._entries).value.key
    }
)
