-- Iteration scans initialized slots, skips tombstones, and never invokes policy code.
-- Table order is unspecified. The owner loan retains the table shape generation.
HashMapEntry#(.key: Type: ImplicitlyCopyable, .value: Type: ImplicitlyCopyable): Type = (
    .key   : key,
    .value : value
)

HashMapEntry#(.key: Type: ImplicitlyCopyable, .value: Type: ImplicitlyCopyable) implements ImplicitlyCopyable

HashMapROEntry#(.key: Type: ImplicitlyCopyable, .value: Type: ImplicitlyCopyable): Type = (
    .key   : &key,
    .value : &value
)

HashMapROEntry#(.key: Type: ImplicitlyCopyable, .value: Type: ImplicitlyCopyable) implements ImplicitlyCopyable

HashMapRWEntry#(.key: Type: ImplicitlyCopyable, .value: Type: ImplicitlyCopyable): Type = (
    .key   : &key,
    .value : $&value
)

HashMapRWEntry#(.key: Type: ImplicitlyCopyable, .value: Type: ImplicitlyCopyable) implements ImplicitlyCopyable

_hash_map_next_index#(
        .key    : Type: ImplicitlyCopyable,
        .value  : Type: ImplicitlyCopyable,
        .policy : Type: HashPolicy#(.key: key)
    )(
        .self  : &HashMap#(.key: key, .value: value, .policy: policy),
        .start : UIntNative
    ) -> (
        .index : UIntNative
    ) := {
    index = start
    count ::= capacity(self).count

    while index < count {
        slot ::= _trusted_dynamic_array_get(.array = &self&._slots, .index = index)
        if is(.value = slot, .variant = ..occupied) { return }
        index = index + 1
    }
}

HashMap#(
    .key    : Type: ImplicitlyCopyable,
    .value  : Type: ImplicitlyCopyable,
    .policy : Type: HashPolicy#(.key: key)
) implements Iterable#(.t: HashMapEntry#(.key: key, .value: value))

HashMapIterator#(
    .key    : Type: ImplicitlyCopyable,
    .value  : Type: ImplicitlyCopyable,
    .policy : Type: HashPolicy#(.key: key)
): Type = (
    ._owner : &HashMap#(.key: key, .value: value, .policy: policy),
    ._index : UIntNative
)

HashMapIterator#(
    .key    : Type: ImplicitlyCopyable,
    .value  : Type: ImplicitlyCopyable,
    .policy : Type: HashPolicy#(.key: key)
) implements Iterator#(.t: HashMapEntry#(.key: key, .value: value))

to_iterator#(
        .key    : Type: ImplicitlyCopyable,
        .value  : Type: ImplicitlyCopyable,
        .policy : Type: HashPolicy#(.key: key)
    )(
        .value : &HashMap#(.key: key, .value: value, .policy: policy)
    ) -> (
        .iterator : HashMapIterator#(.key: key, .value: value, .policy: policy)
    ) := {
    owner ::= depend_on#(.t: &HashMap#(.key: key, .value: value, .policy: policy))(
        .value = value
        .on    = erase_reference#(.t: _DynamicArrayShape)(.base = &value&._slots._shape).reference
    ).result
    iterator = (
        ._owner = owner
        ._index = 0
    )
}

has_next#(
        .key    : Type: ImplicitlyCopyable,
        .value  : Type: ImplicitlyCopyable,
        .policy : Type: HashPolicy#(.key: key)
    )(
        .self : &HashMapIterator#(.key: key, .value: value, .policy: policy)
    ) -> (
        .ok : Bool
    ) := {
    ok = [
        _hash_map_next_index(self&._owner, .start = self&._index).index
        < capacity(self&._owner).count
    ]
}

next#(
        .key    : Type: ImplicitlyCopyable,
        .value  : Type: ImplicitlyCopyable,
        .policy : Type: HashPolicy#(.key: key)
    )(
        .self : $&HashMapIterator#(.key: key, .value: value, .policy: policy)
    ) -> (
        .value : HashMapEntry#(.key: key, .value: value)
    ) := {
    index ::= _hash_map_next_index(self&._owner, .start = self&._index).index

    if index >= capacity(self&._owner).count { abort }
    slot ::= _trusted_dynamic_array_get(.array = &self&._owner&._slots, .index = index)
    self&._index = index + 1

    match slot {
        ..occupied entry { value = (.key = entry.key, .value = entry.value) }
        ..empty { abort }
        ..deleted { abort }
    }
}

HashMapKeyIterator#(
    .key    : Type: ImplicitlyCopyable,
    .value  : Type: ImplicitlyCopyable,
    .policy : Type: HashPolicy#(.key: key)
): Type = (
    ._owner : &HashMap#(.key: key, .value: value, .policy: policy),
    ._index : UIntNative
)

HashMapKeyIterator#(
    .key    : Type: ImplicitlyCopyable,
    .value  : Type: ImplicitlyCopyable,
    .policy : Type: HashPolicy#(.key: key)
) implements Iterator#(.t: key)

to_key_iterator#(
        .key    : Type: ImplicitlyCopyable,
        .value  : Type: ImplicitlyCopyable,
        .policy : Type: HashPolicy#(.key: key)
    )(
        .value : &HashMap#(.key: key, .value: value, .policy: policy)
    ) -> (
        .iterator : HashMapKeyIterator#(.key: key, .value: value, .policy: policy)
    ) := {
    owner ::= depend_on#(.t: &HashMap#(.key: key, .value: value, .policy: policy))(
        .value = value
        .on    = erase_reference#(.t: _DynamicArrayShape)(.base = &value&._slots._shape).reference
    ).result
    iterator = (
        ._owner = owner
        ._index = 0
    )
}

has_next#(
        .key    : Type: ImplicitlyCopyable,
        .value  : Type: ImplicitlyCopyable,
        .policy : Type: HashPolicy#(.key: key)
    )(
        .self : &HashMapKeyIterator#(.key: key, .value: value, .policy: policy)
    ) -> (
        .ok : Bool
    ) := {
    ok = [
        _hash_map_next_index(self&._owner, .start = self&._index).index
        < capacity(self&._owner).count
    ]
}

next#(
        .key    : Type: ImplicitlyCopyable,
        .value  : Type: ImplicitlyCopyable,
        .policy : Type: HashPolicy#(.key: key)
    )(
        .self : $&HashMapKeyIterator#(.key: key, .value: value, .policy: policy)
    ) -> (
        .value : key
    ) := {
    index ::= _hash_map_next_index(self&._owner, .start = self&._index).index

    if index >= capacity(self&._owner).count { abort }
    slot ::= _trusted_dynamic_array_get(.array = &self&._owner&._slots, .index = index)
    self&._index = index + 1

    match slot {
        ..occupied entry { value = entry.key }
        ..empty { abort }
        ..deleted { abort }
    }
}

HashMapValueIterator#(
    .key    : Type: ImplicitlyCopyable,
    .value  : Type: ImplicitlyCopyable,
    .policy : Type: HashPolicy#(.key: key)
): Type = (
    ._owner : &HashMap#(.key: key, .value: value, .policy: policy),
    ._index : UIntNative
)

HashMapValueIterator#(
    .key    : Type: ImplicitlyCopyable,
    .value  : Type: ImplicitlyCopyable,
    .policy : Type: HashPolicy#(.key: key)
) implements Iterator#(.t: value)

to_value_iterator#(
        .key    : Type: ImplicitlyCopyable,
        .value  : Type: ImplicitlyCopyable,
        .policy : Type: HashPolicy#(.key: key)
    )(
        .value : &HashMap#(.key: key, .value: value, .policy: policy)
    ) -> (
        .iterator : HashMapValueIterator#(.key: key, .value: value, .policy: policy)
    ) := {
    owner ::= depend_on#(.t: &HashMap#(.key: key, .value: value, .policy: policy))(
        .value = value
        .on    = erase_reference#(.t: _DynamicArrayShape)(.base = &value&._slots._shape).reference
    ).result
    iterator = (
        ._owner = owner
        ._index = 0
    )
}

has_next#(
        .key    : Type: ImplicitlyCopyable,
        .value  : Type: ImplicitlyCopyable,
        .policy : Type: HashPolicy#(.key: key)
    )(
        .self : &HashMapValueIterator#(.key: key, .value: value, .policy: policy)
    ) -> (
        .ok : Bool
    ) := {
    ok = [
        _hash_map_next_index(self&._owner, .start = self&._index).index
        < capacity(self&._owner).count
    ]
}

next#(
        .key    : Type: ImplicitlyCopyable,
        .value  : Type: ImplicitlyCopyable,
        .policy : Type: HashPolicy#(.key: key)
    )(
        .self : $&HashMapValueIterator#(.key: key, .value: value, .policy: policy)
    ) -> (
        .value : value
    ) := {
    index ::= _hash_map_next_index(self&._owner, .start = self&._index).index

    if index >= capacity(self&._owner).count { abort }
    slot ::= _trusted_dynamic_array_get(.array = &self&._owner&._slots, .index = index)
    self&._index = index + 1

    match slot {
        ..occupied entry { value = entry.value }
        ..empty { abort }
        ..deleted { abort }
    }
}

-- Borrowed results retain a direct shape anchor independently of owner storage.
HashMapROEntryIterator#(
    .key    : Type: ImplicitlyCopyable,
    .value  : Type: ImplicitlyCopyable,
    .policy : Type: HashPolicy#(.key: key)
): Type = (
    ._owner      : &HashMap#(.key: key, .value: value, .policy: policy),
    ._generation : &Any,
    ._index      : UIntNative
)

HashMapROEntryIterator#(
    .key    : Type: ImplicitlyCopyable,
    .value  : Type: ImplicitlyCopyable,
    .policy : Type: HashPolicy#(.key: key)
) implements Iterator#(.t: HashMapROEntry#(.key: key, .value: value))

to_ro_entry_iterator#(
        .key    : Type: ImplicitlyCopyable,
        .value  : Type: ImplicitlyCopyable,
        .policy : Type: HashPolicy#(.key: key)
    )(
        .value : &HashMap#(.key: key, .value: value, .policy: policy)
    ) -> (
        .iterator : HashMapROEntryIterator#(.key: key, .value: value, .policy: policy)
    ) := {
    owner ::= depend_on#(.t: &HashMap#(.key: key, .value: value, .policy: policy))(
        .value = value
        .on    = erase_reference#(.t: _DynamicArrayShape)(.base = &value&._slots._shape).reference
    ).result
    iterator = (
        ._owner      = owner
        ._generation = erase_reference#(.t: _DynamicArrayShape)(.base = &value&._slots._shape).reference
        ._index      = 0
    )
}

has_next#(
        .key    : Type: ImplicitlyCopyable,
        .value  : Type: ImplicitlyCopyable,
        .policy : Type: HashPolicy#(.key: key)
    )(
        .self : &HashMapROEntryIterator#(.key: key, .value: value, .policy: policy)
    ) -> (
        .ok : Bool
    ) := {
    ok = [
        _hash_map_next_index(self&._owner, .start = self&._index).index
        < capacity(self&._owner).count
    ]
}

next#(
        .key    : Type: ImplicitlyCopyable,
        .value  : Type: ImplicitlyCopyable,
        .policy : Type: HashPolicy#(.key: key)
    )(
        .self : $&HashMapROEntryIterator#(.key: key, .value: value, .policy: policy)
    ) -> (
        .value : HashMapROEntry#(.key: key, .value: value)
    ) := {
    index ::= _hash_map_next_index(self&._owner, .start = self&._index).index

    if index >= capacity(self&._owner).count { abort }
    slot ::= dynamic_array_element_ro_pointer(.array = &self&._owner&._slots, .offset = index).pointer
    self&._index = index + 1

    match slot&{
        ..occupied&entry {
            borrowed_key ::= depend_on#(.t: &key)(
                .value = &entry&.key
                .on    = self&._generation
            ).result
            borrowed_value ::= depend_on#(.t: &value)(
                .value = &entry&.value
                .on    = self&._generation
            ).result
            value = depend_on#(.t: HashMapROEntry#(.key: key, .value: value))(
                .value = (.key = borrowed_key, .value = borrowed_value)
                .on    = self&._generation
            ).result
        }
        ..empty { abort }
        ..deleted { abort }
    }
}

HashMapRWEntryIterator#(
    .key    : Type: ImplicitlyCopyable,
    .value  : Type: ImplicitlyCopyable,
    .policy : Type: HashPolicy#(.key: key)
): Type = (
    ._owner      : $&HashMap#(.key: key, .value: value, .policy: policy),
    ._generation : &Any,
    ._index      : UIntNative
)

HashMapRWEntryIterator#(
    .key    : Type: ImplicitlyCopyable,
    .value  : Type: ImplicitlyCopyable,
    .policy : Type: HashPolicy#(.key: key)
) implements Iterator#(.t: HashMapRWEntry#(.key: key, .value: value))

to_rw_entry_iterator#(
        .key    : Type: ImplicitlyCopyable,
        .value  : Type: ImplicitlyCopyable,
        .policy : Type: HashPolicy#(.key: key)
    )(
        .value : $&HashMap#(.key: key, .value: value, .policy: policy)
    ) -> (
        .iterator : HashMapRWEntryIterator#(.key: key, .value: value, .policy: policy)
    ) := {
    owner ::= depend_on#(.t: $&HashMap#(.key: key, .value: value, .policy: policy))(
        .value = value
        .on    = erase_reference#(.t: _DynamicArrayShape)(.base = &value&._slots._shape).reference
    ).result
    iterator = (
        ._owner      = owner
        ._generation = erase_reference#(.t: _DynamicArrayShape)(.base = &value&._slots._shape).reference
        ._index      = 0
    )
}

has_next#(
        .key    : Type: ImplicitlyCopyable,
        .value  : Type: ImplicitlyCopyable,
        .policy : Type: HashPolicy#(.key: key)
    )(
        .self : &HashMapRWEntryIterator#(.key: key, .value: value, .policy: policy)
    ) -> (
        .ok : Bool
    ) := {
    ok = [
        _hash_map_next_index(self&._owner, .start = self&._index).index
        < capacity(self&._owner).count
    ]
}

next#(
        .key    : Type: ImplicitlyCopyable,
        .value  : Type: ImplicitlyCopyable,
        .policy : Type: HashPolicy#(.key: key)
    )(
        .self : $&HashMapRWEntryIterator#(.key: key, .value: value, .policy: policy)
    ) -> (
        .value : HashMapRWEntry#(.key: key, .value: value)
    ) := {
    index ::= _hash_map_next_index(self&._owner, .start = self&._index).index

    if index >= capacity(self&._owner).count { abort }
    slot ::= dynamic_array_element_rw_pointer(.array = $&self&._owner&._slots, .offset = index).pointer
    self&._index = index + 1

    match slot&{
        ..occupied&entry {
            borrowed_key ::= depend_on#(.t: &key)(
                .value = &entry&.key
                .on    = self&._generation
            ).result
            borrowed_value ::= depend_on#(.t: $&value)(
                .value = $&entry&.value
                .on    = self&._generation
            ).result
            value = depend_on#(.t: HashMapRWEntry#(.key: key, .value: value))(
                .value = (.key = borrowed_key, .value = borrowed_value)
                .on    = self&._generation
            ).result
        }
        ..empty { abort }
        ..deleted { abort }
    }
}
