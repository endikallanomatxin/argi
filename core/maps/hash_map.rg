_HashMapSlot#(.key: Type: ImplicitlyCopyable, .value: Type: ImplicitlyCopyable) : Type = (
    ..empty,
    ..deleted,
    ..occupied (.hash: UIntNative, .key: key, .value: value),
)
_HashMapSlot#(.key: Type: ImplicitlyCopyable, .value: Type: ImplicitlyCopyable) implements ImplicitlyCopyable

-- Slots are private and always initialized. Tombstones preserve probe paths;
-- capacity is a slot count independent of powers of two and live load is at most one half.
HashMap#(.key: Type: ImplicitlyCopyable, .value: Type: ImplicitlyCopyable, .policy: Type: HashPolicy#(.key: key)) : Type = (
    ._slots: DynamicArray#(.t: _HashMapSlot#(.key: key, .value: value))
    ._length: UIntNative
    ._policy: policy
)

_hash_map_slots#(.key: Type: ImplicitlyCopyable, .value: Type: ImplicitlyCopyable)(
    .capacity: UIntNative, .allocator: $&Allocator,
) -> (.result: Errable#(.t: DynamicArray#(.t: _HashMapSlot#(.key: key, .value: value)), .reasons: (..out_of_memory))) := {
    slots ::= DynamicArray#(.t: _HashMapSlot#(.key: key, .value: value))(.capacity = capacity, .allocator = allocator)!
    index :: UIntNative = 0
    while index < capacity {
        empty :: _HashMapSlot#(.key: key, .value: value) = ..empty
        push_assume_capacity(.self = $&slots, .value = empty)
        index = index + 1
    }
    result = ..ok ~slots
}

HashMap init#(.key: Type: ImplicitlyCopyable, .value: Type: ImplicitlyCopyable, .policy: Type: HashPolicy#(.key: key))(.policy: policy, .allocator: $&Allocator, .capacity: UIntNative = 8) -> (.result: Errable#(.t: HashMap#(.key: key, .value: value, .policy: policy), .reasons: (..out_of_memory))) := {
    constructed :: HashMap#(.key: key, .value: value, .policy: policy)

    count ::= capacity
    if count < 8 { count = 8 }
    slots ::= _hash_map_slots#(.key: key, .value: value)(.capacity = count, .allocator = allocator)!
    constructed = (._slots = ~slots, ._length = 0, ._policy = ~policy)
    result = ..ok ~constructed
}

length#(.key: Type: ImplicitlyCopyable, .value: Type: ImplicitlyCopyable, .policy: Type: HashPolicy#(.key: key))(.self: &HashMap#(.key: key, .value: value, .policy: policy)) -> (.count: UIntNative) := { count = self&._length }
capacity#(.key: Type: ImplicitlyCopyable, .value: Type: ImplicitlyCopyable, .policy: Type: HashPolicy#(.key: key))(.self: &HashMap#(.key: key, .value: value, .policy: policy)) -> (.count: UIntNative) := { count = length(.self = &self&._slots).count }

_hash_map_find#(.key: Type: ImplicitlyCopyable, .value: Type: ImplicitlyCopyable, .policy: Type: HashPolicy#(.key: key))(.self: &HashMap#(.key: key, .value: value, .policy: policy), .key: key, .hash: UIntNative) -> (.index: ?UIntNative) := {
    count ::= capacity(.self = self).count
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
                if entry.hash == hash and eql(.self = &self&._policy, .left = entry.key, .right = key).ok {
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

_hash_map_insert_slot#(.key: Type: ImplicitlyCopyable, .value: Type: ImplicitlyCopyable)(
    .slots: $&DynamicArray#(.t: _HashMapSlot#(.key: key, .value: value)), .key: key, .value: value, .hash: UIntNative,
) -> () := {
    count ::= length(.self = slots).count
    position ::= hash % count
    visited :: UIntNative = 0
    while visited < count {
        slot ::= _trusted_dynamic_array_get(.array = slots, .index = position)
        if is(.value = slot, .variant = ..occupied) == false {
            inserted :: _HashMapSlot#(.key: key, .value: value) = ..occupied (.hash = hash, .key = key, .value = value)
            _trusted_dynamic_array_set(.array = slots, .index = position, .value = inserted)
            return
        }
        position = position + 1
        if position == count { position = 0 }
        visited = visited + 1
    }
    abort
}

_hash_map_grow#(.key: Type: ImplicitlyCopyable, .value: Type: ImplicitlyCopyable, .policy: Type: HashPolicy#(.key: key))(.self: $&HashMap#(.key: key, .value: value, .policy: policy), .allocator: $&Allocator) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    old_count ::= capacity(.self = self).count
    new_count ::= old_count * 2
    if new_count <= old_count {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    -- Prepare everything before ending old storage. There are no fallible
    -- operations after allocation succeeds, so allocation failure preserves data.
    fresh ::= _hash_map_slots#(.key: key, .value: value)(.capacity = new_count, .allocator = allocator)!
    index :: UIntNative = 0
    while index < old_count {
        slot ::= _trusted_dynamic_array_get(.array = &self&._slots, .index = index)
        match slot {
            ..empty {}
            ..deleted {}
            ..occupied entry { _hash_map_insert_slot(.slots = $&fresh, .key = entry.key, .value = entry.value, .hash = entry.hash) }
        }
        index = index + 1
    }
    deinit(.self = $&self&._slots, .allocator = allocator)
    self&._slots = ~fresh
    result = ..ok Void()
}

put#(.key: Type: ImplicitlyCopyable, .value: Type: ImplicitlyCopyable, .policy: Type: HashPolicy#(.key: key))(.self: $&HashMap#(.key: key, .value: value, .policy: policy), .key: key, .value: value, .allocator: $&Allocator) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    assume allocator
    digest ::= hash(.self = &self&._policy, .key = key).hash
    match _hash_map_find(.self = self, .key = key, .hash = digest).index {
        ..none {}
        ..some found {
            slot ::= _trusted_dynamic_array_get(.array = &self&._slots, .index = found.value)
            match slot {
                ..occupied entry {
                    replacement :: _HashMapSlot#(.key: key, .value: value) = ..occupied (.hash = entry.hash, .key = entry.key, .value = value)
                    _trusted_dynamic_array_set(.array = $&self&._slots, .index = found.value, .value = replacement)
                    result = ..ok Void()
                    return
                }
                ..empty { abort }
                ..deleted { abort }
            }
        }
    }
    if self&._length >= capacity(.self = self).count / 2 {
        _hash_map_grow(.self = self, .allocator = allocator)!
    }
    _hash_map_insert_slot(.slots = $&self&._slots, .key = key, .value = value, .hash = digest)
    self&._length = self&._length + 1
    result = ..ok Void()
}

get#(.key: Type: ImplicitlyCopyable, .value: Type: ImplicitlyCopyable, .policy: Type: HashPolicy#(.key: key))(.self: &HashMap#(.key: key, .value: value, .policy: policy), .key: key) -> (.result: ?value) := {
    digest ::= hash(.self = &self&._policy, .key = key).hash
    match _hash_map_find(.self = self, .key = key, .hash = digest).index {
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

contains#(.key: Type: ImplicitlyCopyable, .value: Type: ImplicitlyCopyable, .policy: Type: HashPolicy#(.key: key))(.self: &HashMap#(.key: key, .value: value, .policy: policy), .key: key) -> (.ok: Bool) := {
    digest ::= hash(.self = &self&._policy, .key = key).hash
    ok = is(.value = _hash_map_find(.self = self, .key = key, .hash = digest).index, .variant = ..some)
}

get_ro_ref#(.key: Type: ImplicitlyCopyable, .value: Type: ImplicitlyCopyable, .policy: Type: HashPolicy#(.key: key))(.self: &HashMap#(.key: key, .value: value, .policy: policy), .key: key) -> (.result: ?&value) := {
    digest ::= hash(.self = &self&._policy, .key = key).hash
    match _hash_map_find(.self = self, .key = key, .hash = digest).index {
        ..none { result = ..none }
        ..some found {
            reference ::= unwrap_or_abort(.value = get_ro_ref(.self = &self&._slots, .index = found.value))
            match reference& {
                ..occupied & entry {
                    borrowed ::= depend_on#(.t: &value)(.value = &entry&.value, .on = erase_reference#(.t: _HashMapSlot#(.key: key, .value: value))(.base = reference).reference).result
                    result = ..some(.value = borrowed)
                }
                ..empty { abort }
                ..deleted { abort }
            }
        }
    }
}

remove#(.key: Type: ImplicitlyCopyable, .value: Type: ImplicitlyCopyable, .policy: Type: HashPolicy#(.key: key))(.self: $&HashMap#(.key: key, .value: value, .policy: policy), .key: key, .allocator: $&Allocator) -> (.removed: Bool) := {
    assume allocator
    digest ::= hash(.self = &self&._policy, .key = key).hash
    removed = false
    match _hash_map_find(.self = self, .key = key, .hash = digest).index {
        ..none {}
        ..some found {
            deleted :: _HashMapSlot#(.key: key, .value: value) = ..deleted
            _trusted_dynamic_array_set(.array = $&self&._slots, .index = found.value, .value = deleted)
            self&._length = self&._length - 1
            removed = true
        }
    }
}

HashMap deinit#(.key: Type: ImplicitlyCopyable, .value: Type: ImplicitlyCopyable, .policy: Type: HashPolicy#(.key: key))(.self: $&HashMap#(.key: key, .value: value, .policy: policy), .allocator: $&Allocator) -> () := {
    deinit(.self = $&self&._slots, .allocator = allocator)
    trusted_opaque_drop(.slot = $&self&._policy, .allocator = allocator)
}
