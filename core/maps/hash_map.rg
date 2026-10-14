_HashMapSlot#(.key: Type: ImplicitlyCopyable, .value: Type: ImplicitlyCopyable): Type = (
    ..empty,
    ..deleted,
    ..occupied(.hash: UIntNative, .key: key, .value: value),
)

implement#(.key: Type: ImplicitlyCopyable, .value: Type: ImplicitlyCopyable) ImplicitlyCopyable#(_HashMapSlot#(.key: key, .value: value)) ()

-- Slots are private and always initialized. Tombstones preserve probe paths;
-- capacity is a slot count independent of powers of two and live load is at most one half.
HashMap#(
    .key    : Type: ImplicitlyCopyable,
    .value  : Type: ImplicitlyCopyable,
    .policy : Type: HashPolicy#(policy, key)
): Type = (
    ._slots  : DynamicArray#(.t: _HashMapSlot#(.key: key, .value: value))
    ._length : UIntNative
    ._policy : policy
)

_hash_map_slots#(
        .key   : Type: ImplicitlyCopyable,
        .value : Type: ImplicitlyCopyable, .AllocatorType: Type: Allocator#(AllocatorType))(
        .capacity  : UIntNative,
        .allocator : $&AllocatorType,
    ) -> (
        .result : Errable#(
            DynamicArray#(.t: _HashMapSlot#(.key: key, .value: value)),
            (..out_of_memory)
        )
    ) := {
    slots ::= DynamicArray#(.t: _HashMapSlot#(.key: key, .value: value))(
        .capacity  = capacity
        .allocator = allocator
    )!
    index :: UIntNative = 0

    while index < capacity {
        empty :: _HashMapSlot#(.key: key, .value: value) = ..empty
        push_assume_capacity($&slots, .value = empty)
        index = index + 1
    }

    result = ..ok ~slots
}

implement#(
    .key : Type: ImplicitlyCopyable,
    .value : Type: ImplicitlyCopyable,
    .policy : Type: HashPolicy#(policy, key),
    .Provider: Type: Allocator
) Init#(
    HashMap#(.key: key, .value: value, .policy: policy),
    (
        .policy : policy,
        .allocator : $&Provider = reach allocator,
        .capacity : UIntNative = 8,
    )
) (
    .Result: Type = Errable#(HashMap#(.key: key, .value: value, .policy: policy), (..out_of_memory))
    .init = (.args: (
        .policy : policy,
        .allocator : $&Provider = reach allocator,
        .capacity : UIntNative = 8,
    )) -> (.result: Result) {
        policy ::= ~args.policy
        allocator ::= args.allocator
        capacity ::= args.capacity

        constructed :: HashMap#(.key: key, .value: value, .policy: policy)

        count ::= capacity

        if count < 8 { count = 8 }
        slots ::= _hash_map_slots#(.key: key, .value: value)(.capacity = count, .allocator = allocator)!
        constructed = (._slots = ~slots, ._length = 0, ._policy = ~policy)

        result = ..ok ~constructed
    }
)

_collection_length_hash_map#(
        .key    : Type: ImplicitlyCopyable,
        .value  : Type: ImplicitlyCopyable,
        .policy : Type: HashPolicy#(policy, key)
    )(
        .self : &HashMap#(.key: key, .value: value, .policy: policy)
    ) -> (
        .count : UIntNative
    ) := { count = self&._length }

implement#(
        .key    : Type: ImplicitlyCopyable,
        .value  : Type: ImplicitlyCopyable,
        .policy : Type: HashPolicy#(policy, key)
    ) CollectionLength#(HashMap#(.key: key, .value: value, .policy: policy)) (
    .measure_length = _collection_length_hash_map
)

_collection_capacity_hash_map#(
        .key    : Type: ImplicitlyCopyable,
        .value  : Type: ImplicitlyCopyable,
        .policy : Type: HashPolicy#(policy, key)
    )(
        .self : &HashMap#(.key: key, .value: value, .policy: policy)
    ) -> (
        .count : UIntNative
    ) := { count = length(&self&._slots).count }

implement#(
        .key    : Type: ImplicitlyCopyable,
        .value  : Type: ImplicitlyCopyable,
        .policy : Type: HashPolicy#(policy, key)
    ) CollectionCapacity#(HashMap#(.key: key, .value: value, .policy: policy)) (
    .measure_capacity = _collection_capacity_hash_map
)

_hash_map_find#(
        .key    : Type: ImplicitlyCopyable,
        .value  : Type: ImplicitlyCopyable,
        .policy : Type: HashPolicy#(policy, key)
    )(
        .self : &HashMap#(.key: key, .value: value, .policy: policy),
        .key  : key,
        .hash : UIntNative
    ) -> (
        .index : ?UIntNative
    ) := {
    count ::= capacity(self).count
    position ::= hash % count
    visited :: UIntNative = 0

    while visited < count {
        slot ::= _trusted_dynamic_array_get(.array = &self&._slots, .index = position)
        match slot {
            ..empty {
                index = ..none
                return
            }
            ..deleted {}
            ..occupied entry {
                if [
                    entry.hash == hash
                    and HashPolicy#(policy, key).eql(
                        &self&._policy
                        .left  = entry.key
                        .right = key
                    ).ok
                ] {
                    index = ..some(.value = position)
                    return
                }
            }
        }
        position = position + 1
        if position == count { position = 0 }
        visited = visited + 1
    }

    index = ..none
}

_hash_map_insert_slot#(
        .key   : Type: ImplicitlyCopyable,
        .value : Type: ImplicitlyCopyable
    )(
        .slots : $&DynamicArray#(.t: _HashMapSlot#(.key: key, .value: value)),
        .key   : key,
        .value : value,
        .hash  : UIntNative,
    ) -> () := {
    count ::= length(slots).count
    position ::= hash % count
    visited :: UIntNative = 0

    while visited < count {
        slot ::= _trusted_dynamic_array_get(.array = slots, .index = position)
        if is(.value = slot, .variant = ..occupied) == false {
            inserted :: _HashMapSlot#(.key: key, .value: value) = ..occupied(
                .hash  = hash
                .key   = key
                .value = value
            )
            _trusted_dynamic_array_set(.array = slots, .index = position, .value = inserted)
            return
        }
        position = position + 1
        if position == count { position = 0 }
        visited = visited + 1
    }

    abort
}

_hash_map_grow#(
        .key    : Type: ImplicitlyCopyable,
        .value  : Type: ImplicitlyCopyable,
        .policy : Type: HashPolicy#(policy, key), .AllocatorType: Type: Allocator#(AllocatorType))(
        .self      : $&HashMap#(.key: key, .value: value, .policy: policy),
        .allocator : $&AllocatorType
    ) -> (
        .result : Errable#(Void, (..out_of_memory))
    ) := {
    old_count ::= capacity(self).count
    new_count ::= old_count * 2

    if new_count <= old_count {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    -- Prepare everything before ending old storage. There are no fallible
    -- operations after allocation succeeds, so allocation failure preserves data.
    fresh ::= _hash_map_slots#(.key: key, .value: value)(
        .capacity  = new_count
        .allocator = allocator
    )!
    index :: UIntNative = 0

    while index < old_count {
        slot ::= _trusted_dynamic_array_get(.array = &self&._slots, .index = index)
        match slot {
            ..empty {}
            ..deleted {}
            ..occupied entry {
                _hash_map_insert_slot(
                    .slots = $&fresh
                    .key   = entry.key
                    .value = entry.value
                    .hash  = entry.hash
                )
            }
        }
        index = index + 1
    }

    deinit(.self = $&self&._slots)
    self&._slots = ~fresh

    result = ..ok Void()
}

_map_put_hash_map#(
        .key    : Type: ImplicitlyCopyable,
        .value  : Type: ImplicitlyCopyable,
        .policy : Type: HashPolicy#(policy, key), .Provider: Type: Allocator#(Provider)
) := (
        .self      : $&HashMap#(.key: key, .value: value, .policy: policy),
        .key       : key,
        .value     : value,
        .allocator : $&Provider
    ) -> (.result : Errable#(Void, (..out_of_memory))) {
    assume allocator
    digest ::= HashPolicy#(policy, key).hash(&self&._policy, .key = key).hash

    match _hash_map_find(self, .key = key, .hash = digest).index {
        ..none {}
        ..some found {
            slot ::= _trusted_dynamic_array_get(.array = &self&._slots, .index = found.value)
            match slot {
                ..occupied entry {
                    replacement :: _HashMapSlot#(.key: key, .value: value) = ..occupied(
                        .hash  = entry.hash
                        .key   = entry.key
                        .value = value
                    )
                    _trusted_dynamic_array_set(
                        .array = $&self&._slots
                        .index = found.value
                        .value = replacement
                    )
                    result = ..ok Void()
                    return
                }
                ..empty { abort }
                ..deleted { abort }
            }
        }
    }

    if self&._length >= capacity(self).count / 2 {
        _hash_map_grow(self, .allocator = allocator)!
    }

    _hash_map_insert_slot(.slots = $&self&._slots, .key = key, .value = value, .hash = digest)
    self&._length = self&._length + 1

    result = ..ok Void()
}

_map_get_hash_map#(
        .key    : Type: ImplicitlyCopyable,
        .value  : Type: ImplicitlyCopyable,
        .policy : Type: HashPolicy#(policy, key)
    ) := (
        .self : &HashMap#(.key: key, .value: value, .policy: policy),
        .key  : key
    ) -> (.result : ?value) {
    digest ::= HashPolicy#(policy, key).hash(&self&._policy, .key = key).hash

    match _hash_map_find(self, .key = key, .hash = digest).index {
        ..none { result = ..none }
        ..some found {
            slot ::= _trusted_dynamic_array_get(.array = &self&._slots, .index = found.value)
            match slot {
                ..occupied entry { result = ..some(.value = entry.value) }
                ..empty { abort }
                ..deleted { abort }
            }
        }
    }
}

_map_contains_hash_map#(
        .key    : Type: ImplicitlyCopyable,
        .value  : Type: ImplicitlyCopyable,
        .policy : Type: HashPolicy#(policy, key)
    ) := (
        .self : &HashMap#(.key: key, .value: value, .policy: policy),
        .key  : key
    ) -> (.ok : Bool) {
    digest ::= HashPolicy#(policy, key).hash(&self&._policy, .key = key).hash
    ok = is(
        .value   = _hash_map_find(self, .key = key, .hash = digest).index
        .variant = ..some
    )
}

_map_get_ro_ref_hash_map#(
        .key    : Type: ImplicitlyCopyable,
        .value  : Type: ImplicitlyCopyable,
        .policy : Type: HashPolicy#(policy, key)
    ) := (
        .self : &HashMap#(.key: key, .value: value, .policy: policy),
        .key  : key
    ) -> (.result : ?&value) {
    digest ::= HashPolicy#(policy, key).hash(&self&._policy, .key = key).hash

    match _hash_map_find(self, .key = key, .hash = digest).index {
        ..none { result = ..none }
        ..some found {
            reference ::= unwrap_or_abort(
                .value = get_ro_ref(&self&._slots, .index = found.value)
            )
            match reference&{
                ..occupied&entry {
                    borrowed ::= depend_on#(.t: &value)(
                        .value = &entry&.value
                        .on    = erase_reference#(.t: _HashMapSlot#(.key: key, .value: value))(
                            .base = reference
                        ).reference
                    ).result
                    result = ..some(.value = borrowed)
                }
                ..empty { abort }
                ..deleted { abort }
            }
        }
    }
}

_map_remove_hash_map#(
        .key    : Type: ImplicitlyCopyable,
        .value  : Type: ImplicitlyCopyable,
        .policy : Type: HashPolicy#(policy, key), .Provider: Type: Allocator#(Provider)
) := (
        .self      : $&HashMap#(.key: key, .value: value, .policy: policy),
        .key       : key,
        .allocator : $&Provider
    ) -> (.removed : Bool) {
    assume allocator
    digest ::= HashPolicy#(policy, key).hash(&self&._policy, .key = key).hash
    removed = false

    match _hash_map_find(self, .key = key, .hash = digest).index {
        ..none {}
        ..some found {
            deleted :: _HashMapSlot#(.key: key, .value: value) = ..deleted
            _trusted_dynamic_array_set(
                .array = $&self&._slots
                .index = found.value
                .value = deleted
            )
            self&._length = self&._length - 1
            removed = true
        }
    }
}

implement#(
        .key    : Type: ImplicitlyCopyable,
        .value  : Type: ImplicitlyCopyable,
        .policy : Type: HashPolicy#(policy, key)
    ) Deinit#(HashMap#(.key: key, .value: value, .policy: policy)) (
    .deinit = (.self: $&HashMap#(.key: key, .value: value, .policy: policy)) -> () {
        deinit(.self = $&self&._slots)
        policy ::= ~self&._policy
    }
)
