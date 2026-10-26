HashSetIterator := <.key: Type: ImplicitlyCopyable, .policy: Type: HashPolicy<policy, key>> (
    ._keys: HashMapKeyIterator<.key: key, .value: _HashSetValue, .policy: policy>
)

implement<.key: Type: ImplicitlyCopyable, .policy: Type: HashPolicy<policy, key>> Iterable<
    HashSet<.key: key, .policy: policy>
> (
    .Item         : Type = key
    .IteratorType : Type = HashSetIterator<.key: key, .policy: policy>

    .to_iterator = (.value: &HashSet<.key: key, .policy: policy>) -> (
        .iterator: HashSetIterator<.key: key, .policy: policy>
    ) {
        iterator = (._keys = to_key_iterator(.value = &value&._map).iterator)
    }
)

implement<.key: Type: ImplicitlyCopyable, .policy: Type: HashPolicy<policy, key>> Iterator<
    HashSetIterator<.key: key, .policy: policy>
> (
    .Item : Type = key

    .has_next = (.self: &HashSetIterator<.key: key, .policy: policy>) -> (.ok: Bool) {
        ok = has_next(&self&._keys).ok
    }

    .next = (.self: $&HashSetIterator<.key: key, .policy: policy>) -> (.value: key) {
        value = next($&self&._keys).value
    }
)

HashSetReferenceIterator := <.key: Type, .policy: Type: HashPolicy<policy, key>> (
    ._entries: HashMapBorrowIterator<.key: key, .value: _HashSetValue, .policy: policy>
)

implement<.key: Type, .policy: Type: HashPolicy<policy, key>> ReferenceIterable<
    HashSet<.key: key, .policy: policy>
> (
    .Item         : Type = key
    .IteratorType : Type = HashSetReferenceIterator<.key: key, .policy: policy>

    .to_reference_iterator = (.value: &HashSet<.key: key, .policy: policy>) -> (
        .iterator: HashSetReferenceIterator<.key: key, .policy: policy>
    ) { iterator = (._entries = to_iterator(.value = &value&._map).iterator) }
)

implement<.key: Type, .policy: Type: HashPolicy<policy, key>> Iterator<
    HashSetReferenceIterator<.key: key, .policy: policy>
> (
    .Item : Type = &key

    .has_next = (.self: &HashSetReferenceIterator<.key: key, .policy: policy>) -> (.ok: Bool) {
        ok = has_next(&self&._entries).ok
    }

    .next = (.self: $&HashSetReferenceIterator<.key: key, .policy: policy>) -> (
        .value : &key
    ) {
        value = next($&self&._entries).value.key
    }
)
