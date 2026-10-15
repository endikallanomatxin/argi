OwnedHashMapBorrow#(.key: Type, .value: Type): Type = (.key: &key, .value: &value)

implement#(.key: Type, .value: Type) ImplicitlyCopyable#(
    OwnedHashMapBorrow#(.key: key, .value: value)
) ()

OwnedHashMapIterator#(.key: Type, .value: Type, .policy: Type: BorrowedHashPolicy#(policy, key)): Type = (
    ._owner      : &OwnedHashMap#(.key: key, .value: value, .policy: policy),
    ._generation : &Any,
    ._index      : UIntNative
)

_owned_hash_next#(
        .key    : Type,
        .value  : Type,
        .policy : Type: BorrowedHashPolicy#(policy, key)
    )(
        .self  : &OwnedHashMap#(.key: key, .value: value, .policy: policy),
        .start : UIntNative
    ) -> (
        .index : UIntNative
    ) := {
    index = start

    while index < capacity(self).count {
        if _trusted_dynamic_array_get(.array = &self&._table._slots, .index = index).state == 1 {
            return
        }
        index = index + 1
    }
}

OwnedHashSetIterator#(.key: Type, .policy: Type: BorrowedHashPolicy#(policy, key)): Type = (
    ._entries : OwnedHashMapIterator#(.key: key, .value: _HashSetValue, .policy: policy)
)

implement#(
    .key    : Type,
    .value  : Type,
    .policy : Type: BorrowedHashPolicy#(policy, key)
) Iterable#(OwnedHashMap#(.key: key, .value: value, .policy: policy)) (
        .Item         : Type = OwnedHashMapBorrow#(.key: key, .value: value)
        .IteratorType : Type = OwnedHashMapIterator#(.key: key, .value: value, .policy: policy)

        .to_iterator = (
                .value : &OwnedHashMap#(.key: key, .value: value, .policy: policy)
            ) -> (
                .iterator : OwnedHashMapIterator#(.key: key, .value: value, .policy: policy)
            ) {
            generation ::= erase_reference#(.t: _OwnedHashShape)(.base = &value&._shape).reference
            owner ::= depend_on#(.t: &OwnedHashMap#(.key: key, .value: value, .policy: policy))(
                .value = value
                .on    = generation
            ).result
            iterator = (._owner = owner, ._generation = generation, ._index = 0)
        }
    )

implement#(
    .key    : Type,
    .value  : Type,
    .policy : Type: BorrowedHashPolicy#(policy, key)
) Iterator#(OwnedHashMapIterator#(.key: key, .value: value, .policy: policy)) (
        .Item : Type = OwnedHashMapBorrow#(.key: key, .value: value)

        .has_next = (
                .self : &OwnedHashMapIterator#(.key: key, .value: value, .policy: policy)
            ) -> (
                .ok : Bool
            ) {
            ok = [
                _owned_hash_next(self&._owner, .start = self&._index).index
                < capacity(self&._owner).count
            ]
        }

        .next = (
                .self : $&OwnedHashMapIterator#(.key: key, .value: value, .policy: policy)
            ) -> (
                .value : OwnedHashMapBorrow#(.key: key, .value: value)
            ) {
            index ::= _owned_hash_next(self&._owner, .start = self&._index).index

            if index >= capacity(self&._owner).count { abort }
            entry ::= _owned_hash_entry(self&._owner, .index = index).entry
            borrowed_key ::= depend_on#(.t: &key)(.value = &entry&.key, .on = self&._generation).result
            borrowed_value ::= depend_on#(.t: &value)(
                .value = &entry&.value
                .on    = self&._generation
            ).result
            value = (.key = borrowed_key, .value = borrowed_value)
            self&._index = index + 1
        }
    )

implement#(
    .key    : Type,
    .policy : Type: BorrowedHashPolicy#(policy, key)
) ROPointerIterable#(OwnedHashSet#(.key: key, .policy: policy)) (
        .Item         : Type = key
        .IteratorType : Type = OwnedHashSetIterator#(.key: key, .policy: policy)

        .to_ro_pointer_iterator = (
                .value : &OwnedHashSet#(.key: key, .policy: policy)
            ) -> (
                .iterator : OwnedHashSetIterator#(.key: key, .policy: policy)
            ) { iterator = (._entries = to_iterator(.value = &value&._map).iterator) }
    )

implement#(
    .key    : Type,
    .policy : Type: BorrowedHashPolicy#(policy, key)
) Iterator#(OwnedHashSetIterator#(.key: key, .policy: policy)) (
        .Item : Type = &key

        .has_next = (
                .self : &OwnedHashSetIterator#(.key: key, .policy: policy)
            ) -> (
                .ok : Bool
            ) { ok = has_next(&self&._entries).ok }

        .next = (
                .self : $&OwnedHashSetIterator#(.key: key, .policy: policy)
            ) -> (
                .value : &key
            ) { value = next($&self&._entries).value.key }
    )
