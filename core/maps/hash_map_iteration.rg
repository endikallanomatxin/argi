HashMapROEntry := #(.key: Type, .value: Type) (.key: &key, .value: &value)

implement#(.key: Type, .value: Type) ImplicitlyCopyable#(
    HashMapROEntry#(.key: key, .value: value)
) ()

HashMapBorrowIterator := #(.key: Type, .value: Type, .policy: Type: HashPolicy#(policy, key)) (
    ._owner      : &HashMap#(.key: key, .value: value, .policy: policy),
    ._generation : &Any,
    ._index      : UIntNative
)

_hash_next := #(.key: Type, .value: Type, .policy: Type: HashPolicy#(policy, key)) (
    .self: &HashMap#(.key: key, .value: value, .policy: policy), .start: UIntNative
) -> (.index: UIntNative) {
    index = start

    while index < capacity(self).count {
        if _trusted_dynamic_array_get(.array = &self&._table._slots, .index = index).state == 1 {
            return
        }
        index = index + 1
    }
}

implement#(.key: Type, .value: Type, .policy: Type: HashPolicy#(policy, key)) Iterable#(
    HashMap#(.key: key, .value: value, .policy: policy)
) (
    .Item         : Type = HashMapROEntry#(.key: key, .value: value)
    .IteratorType : Type = HashMapBorrowIterator#(.key: key, .value: value, .policy: policy)

    .to_iterator = (.value: &HashMap#(.key: key, .value: value, .policy: policy)) -> (
        .iterator : HashMapBorrowIterator#(.key: key, .value: value, .policy: policy)
    ) {
        generation ::= erase_reference#(.t: _HashShape)(.base = &value&._shape).reference
        owner ::= depend_on#(.t: &HashMap#(.key: key, .value: value, .policy: policy))(
            .value = value, .on = generation
        ).result
        iterator = (._owner = owner, ._generation = generation, ._index = 0)
    }
)

implement#(.key: Type, .value: Type, .policy: Type: HashPolicy#(policy, key)) Iterator#(
    HashMapBorrowIterator#(.key: key, .value: value, .policy: policy)
) (
    .Item : Type = HashMapROEntry#(.key: key, .value: value)

    .has_next = (.self: &HashMapBorrowIterator#(.key: key, .value: value, .policy: policy)) -> (
        .ok : Bool
    ) {
        ok = [
            _hash_next(self&._owner, .start = self&._index).index
            < capacity(self&._owner).count
        ]
    }

    .next = (.self: $&HashMapBorrowIterator#(.key: key, .value: value, .policy: policy)) -> (
        .value : HashMapROEntry#(.key: key, .value: value)
    ) {
        index ::= _hash_next(self&._owner, .start = self&._index).index

        if index >= capacity(self&._owner).count { abort }
        entry ::= _hash_entry(self&._owner, .index = index).entry
        borrowed_key ::= depend_on#(.t: &key)(
            .value = &entry&.key, .on = self&._generation
        ).result
        borrowed_value ::= depend_on#(.t: &value)(
            .value = &entry&.value, .on = self&._generation
        ).result
        value = (.key = borrowed_key, .value = borrowed_value)
        self&._index = index + 1
    }
)

-- Iteration scans initialized slots, skips tombstones, and never invokes policy code.
-- Table order is unspecified. The owner loan retains the table shape generation.
HashMapRWEntry := #(.key: Type, .value: Type) (
    .key   : &key,
    .value : $&value
)

implement#(.key: Type, .value: Type) ImplicitlyCopyable#(
    HashMapRWEntry#(.key: key, .value: value)
) ()

HashMapKeyIterator := #(
    .key: Type: ImplicitlyCopyable, .value: Type, .policy: Type: HashPolicy#(policy, key)
) (
    ._owner : &HashMap#(.key: key, .value: value, .policy: policy),
    ._index : UIntNative
)

to_key_iterator := #(
    .key: Type: ImplicitlyCopyable, .value: Type, .policy: Type: HashPolicy#(policy, key)
) (.value: &HashMap#(.key: key, .value: value, .policy: policy)) -> (
    .iterator : HashMapKeyIterator#(.key: key, .value: value, .policy: policy)
) {
    owner ::= depend_on#(.t: &HashMap#(.key: key, .value: value, .policy: policy))(
        .value = value, .on = erase_reference#(.t: _HashShape)(.base = &value&._shape).reference
    ).result
    iterator = (
        ._owner = owner
        ._index = 0
    )
}

HashMapValueIterator := #(
    .key: Type, .value: Type: ImplicitlyCopyable, .policy: Type: HashPolicy#(policy, key)
) (
    ._owner : &HashMap#(.key: key, .value: value, .policy: policy),
    ._index : UIntNative
)

to_value_iterator := #(
    .key: Type, .value: Type: ImplicitlyCopyable, .policy: Type: HashPolicy#(policy, key)
) (.value: &HashMap#(.key: key, .value: value, .policy: policy)) -> (
    .iterator : HashMapValueIterator#(.key: key, .value: value, .policy: policy)
) {
    owner ::= depend_on#(.t: &HashMap#(.key: key, .value: value, .policy: policy))(
        .value = value, .on = erase_reference#(.t: _HashShape)(.base = &value&._shape).reference
    ).result
    iterator = (
        ._owner = owner
        ._index = 0
    )
}

to_ro_entry_iterator := #(.key: Type, .value: Type, .policy: Type: HashPolicy#(policy, key)) (
    .value : &HashMap#(.key: key, .value: value, .policy: policy)
) -> (.iterator: HashMapBorrowIterator#(.key: key, .value: value, .policy: policy)) {
    iterator = to_iterator(.value = value).iterator
}

HashMapRWEntryIterator := #(.key: Type, .value: Type, .policy: Type: HashPolicy#(policy, key)) (
    ._owner      : $&HashMap#(.key: key, .value: value, .policy: policy),
    ._generation : &Any,
    ._index      : UIntNative
)

to_rw_entry_iterator := #(.key: Type, .value: Type, .policy: Type: HashPolicy#(policy, key)) (
    .value : $&HashMap#(.key: key, .value: value, .policy: policy)
) -> (.iterator: HashMapRWEntryIterator#(.key: key, .value: value, .policy: policy)) {
    owner ::= depend_on#(.t: $&HashMap#(.key: key, .value: value, .policy: policy))(
        .value = value, .on = erase_reference#(.t: _HashShape)(.base = &value&._shape).reference
    ).result
    iterator = (
        ._owner      = owner
        ._generation = erase_reference#(.t: _HashShape)(.base = &value&._shape).reference
        ._index      = 0
    )
}

implement#(
    .key: Type: ImplicitlyCopyable, .value: Type, .policy: Type: HashPolicy#(policy, key)
) Iterator#(HashMapKeyIterator#(.key: key, .value: value, .policy: policy)) (
    .Item : Type = key

    .has_next = (.self: &HashMapKeyIterator#(.key: key, .value: value, .policy: policy)) -> (
        .ok : Bool
    ) {
        ok = [
            _hash_next(self&._owner, .start = self&._index).index
            < capacity(self&._owner).count
        ]
    }

    .next = (.self: $&HashMapKeyIterator#(.key: key, .value: value, .policy: policy)) -> (
        .value : key
    ) {
        index ::= _hash_next(self&._owner, .start = self&._index).index

        if index >= capacity(self&._owner).count { abort }
        entry ::= _hash_entry(self&._owner, .index = index).entry
        self&._index = index + 1
        value = entry&.key
    }
)

implement#(
    .key: Type, .value: Type: ImplicitlyCopyable, .policy: Type: HashPolicy#(policy, key)
) Iterator#(HashMapValueIterator#(.key: key, .value: value, .policy: policy)) (
    .Item : Type = value

    .has_next = (.self: &HashMapValueIterator#(.key: key, .value: value, .policy: policy)) -> (
        .ok : Bool
    ) {
        ok = [
            _hash_next(self&._owner, .start = self&._index).index
            < capacity(self&._owner).count
        ]
    }

    .next = (.self: $&HashMapValueIterator#(.key: key, .value: value, .policy: policy)) -> (
        .value : value
    ) {
        index ::= _hash_next(self&._owner, .start = self&._index).index

        if index >= capacity(self&._owner).count { abort }
        entry ::= _hash_entry(self&._owner, .index = index).entry
        self&._index = index + 1
        value = entry&.value
    }
)

implement#(.key: Type, .value: Type, .policy: Type: HashPolicy#(policy, key)) Iterator#(
    HashMapRWEntryIterator#(.key: key, .value: value, .policy: policy)
) (
    .Item : Type = HashMapRWEntry#(.key: key, .value: value)

    .has_next = (.self: &HashMapRWEntryIterator#(.key: key, .value: value, .policy: policy)) -> (
        .ok : Bool
    ) {
        ok = [
            _hash_next(self&._owner, .start = self&._index).index
            < capacity(self&._owner).count
        ]
    }

    .next = (.self: $&HashMapRWEntryIterator#(.key: key, .value: value, .policy: policy)) -> (
        .value : HashMapRWEntry#(.key: key, .value: value)
    ) {
        index ::= _hash_next(self&._owner, .start = self&._index).index

        if index >= capacity(self&._owner).count { abort }
        entry ::= _hash_entry(self&._owner, .index = index).entry
        self&._index = index + 1
        borrowed_key ::= depend_on#(.t: &key)(
            .value = &entry&.key, .on = self&._generation
        ).result
        borrowed_value ::= depend_on#(.t: $&value)(
            .value = $&entry&.value, .on = self&._generation
        ).result
        value = (.key = borrowed_key, .value = borrowed_value)
    }
)
