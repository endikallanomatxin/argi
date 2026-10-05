HashSetIterator#(.key: Type: ImplicitlyCopyable, .policy: Type: HashPolicy#(.key: key)): Type = (
    ._keys : HashMapKeyIterator#(.key: key, .value: _HashSetValue, .policy: policy)
)

HashSetIterator#(.key: Type: ImplicitlyCopyable, .policy: Type: HashPolicy#(.key: key)) implements Iterator#(
    .t : key
)
HashSet#(.key: Type: ImplicitlyCopyable, .policy: Type: HashPolicy#(.key: key)) implements Iterable#(
    .t : key
)

to_iterator#(
        .key    : Type: ImplicitlyCopyable,
        .policy : Type: HashPolicy#(.key: key)
    )(
        .value : &HashSet#(.key: key, .policy: policy)
    ) -> (
        .iterator : HashSetIterator#(.key: key, .policy: policy)
    ) := {
    iterator = (._keys = to_key_iterator(.value = &value&._map).iterator)
}

has_next#(
        .key    : Type: ImplicitlyCopyable,
        .policy : Type: HashPolicy#(.key: key)
    )(
        .self : &HashSetIterator#(.key: key, .policy: policy)
    ) -> (
        .ok : Bool
    ) := {
    ok = has_next(&self&._keys).ok
}

next#(
        .key    : Type: ImplicitlyCopyable,
        .policy : Type: HashPolicy#(.key: key)
    )(
        .self : $&HashSetIterator#(.key: key, .policy: policy)
    ) -> (
        .value : key
    ) := {
    value = next($&self&._keys).value
}
