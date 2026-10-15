HashSetIterator#(.key: Type: ImplicitlyCopyable, .policy: Type: HashPolicy#(policy, key)): Type = (
    ._keys : HashMapKeyIterator#(.key: key, .value: _HashSetValue, .policy: policy)
)

implement#(
    .key    : Type: ImplicitlyCopyable,
    .policy : Type: HashPolicy#(policy, key)
) Iterable#(HashSet#(.key: key, .policy: policy)) (
        .Item         : Type = key
        .IteratorType : Type = HashSetIterator#(.key: key, .policy: policy)

        .to_iterator = (
                .value : &HashSet#(.key: key, .policy: policy)
            ) -> (
                .iterator : HashSetIterator#(.key: key, .policy: policy)
            ) {
            iterator = (._keys = to_key_iterator(.value = &value&._map).iterator)
        }
    )

implement#(
    .key    : Type: ImplicitlyCopyable,
    .policy : Type: HashPolicy#(policy, key)
) Iterator#(HashSetIterator#(.key: key, .policy: policy)) (
        .Item : Type = key

        .has_next = (
                .self : &HashSetIterator#(.key: key, .policy: policy)
            ) -> (
                .ok : Bool
            ) {
            ok = has_next(&self&._keys).ok
        }

        .next = (
                .self : $&HashSetIterator#(.key: key, .policy: policy)
            ) -> (
                .value : key
            ) {
            value = next($&self&._keys).value
        }
    )
