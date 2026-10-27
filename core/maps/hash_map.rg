-- Inputs rejected by insertion are destroyed through ordinary lexical cleanup.
_hash_discard := #(.t: Type, .AllocatorType: Type: Allocator#(AllocatorType)) (
    .value: t, .allocator: $&AllocatorType
) -> () {
    assume allocator
    discarded ::= ~value
}

HashMapEntry := #(.key: Type, .value: Type) (.key: key, .value: value)

implement#(.key: Type: ImplicitlyCopyable, .value: Type: ImplicitlyCopyable) ImplicitlyCopyable#(
    HashMapEntry#(.key: key, .value: value)
) ()

_HashSlot := (.state: UInt8, .hash: UIntNative)

implement ImplicitlyCopyable#(_HashSlot) ()

_HashTable := (._entries: Allocation, ._slots: DynamicArray#(.t: _HashSlot))

_HashShape := (.marker: UInt8 = 0)

implement Deinit#(_HashShape) (
    .deinit = (.self: $&_HashShape) -> () {
    }
)

-- Metadata is always initialized: 0 empty, 1 occupied, 2 deleted. Only occupied
-- indices contain owning entries in the separate allocation. Vacant entry slots
-- are never borrowed, read, or destroyed. Probes are bounded by slot capacity.
HashMap := #(
    .key: Type, .value: Type, .policy: Type: HashPolicy#(policy, key) = StandardHashPolicy
) (
    ._table  : _HashTable,
    ._length : UIntNative,
    ._policy : policy,
    ._shape  : _HashShape
)

_hash_slots := #(.AllocatorType: Type: Allocator#(AllocatorType)) (
    .capacity: UIntNative, .allocator: $&AllocatorType
) -> (.result: Errable#(DynamicArray#(.t: _HashSlot), (..out_of_memory))) {
    slots ::= DynamicArray#(.t: _HashSlot)(.capacity = capacity, .allocator = allocator)!
    index :: UIntNative = 0

    while index < capacity {
        push_assume_capacity($&slots, .value = _HashSlot(.state = 0, .hash = 0))
        index = index + 1
    }

    result = ..ok ~slots
}

_init_hash_map := #(
    .key      : Type,
    .value    : Type,
    .policy   : Type: HashPolicy#(policy, key),
    .Provider : Type: Allocator
) (.policy: policy, .allocator: $&Provider, .capacity: UIntNative) -> (
    .result : Errable#(HashMap#(.key: key, .value: value, .policy: policy), (..out_of_memory))
) {
    constructed :: HashMap#(.key: key, .value: value, .policy: policy)
    assume allocator
    owned_policy ::= ~policy
    count ::= capacity

    if count < 8 { count = 8 }
    slots ::= _hash_slots(.capacity = count, .allocator = allocator)!
    entries ::= allocate#(.t: HashMapEntry#(.key: key, .value: value))(
        allocator, .count = count
    )!
    constructed = (
        ._table  = (._entries = ~entries, ._slots = ~slots)
        ._length = 0
        ._policy = ~owned_policy
        ._shape  = (.marker = 0)
    )

    result = ..ok ~constructed
}

implement#(.key: Type, .value: Type, .policy: Type: HashPolicy#(policy, key)) Init#(
    HashMap#(.key: key, .value: value, .policy: policy)
) (
    .init = #(.Provider: Type: Allocator) (
        .policy: policy, .allocator: $&Provider, .capacity: UIntNative = 8
    ) -> (
        .result : Errable#(
            HashMap#(.key: key, .value: value, .policy: policy), (..out_of_memory)
        )
    ) {
        constructed ::= _init_hash_map#(.key: key, .value: value)(
            .policy = ~policy, .allocator = allocator, .capacity = capacity
        )!
        result = ..ok ~constructed
    }
)

implement#(.key: Type: _StandardHashKey#(key), .value: Type) Init#(
    HashMap#(.key: key, .value: value, .policy: StandardHashPolicy)
) (
    .init = #(.Provider: Type: Allocator) (
        .policy    : StandardHashPolicy = StandardHashPolicy(),
        .allocator : $&Provider,
        .capacity  : UIntNative         = 8
    ) -> (
        .result : Errable#(
            HashMap#(.key: key, .value: value, .policy: StandardHashPolicy), (..out_of_memory)
        )
    ) {
        constructed ::= _init_hash_map#(.key: key, .value: value)(
            .policy = ~policy, .allocator = allocator, .capacity = capacity
        )!
        result = ..ok ~constructed
    }
)

_collection_length_hash_map := #(
    .key: Type, .value: Type, .policy: Type: HashPolicy#(policy, key)
) (.self: &HashMap#(.key: key, .value: value, .policy: policy)) -> (.count: UIntNative) {
    count = self&._length
}

implement#(.key: Type, .value: Type, .policy: Type: HashPolicy#(policy, key)) CollectionLength#(
    HashMap#(.key: key, .value: value, .policy: policy)
) (
    .measure_length = _collection_length_hash_map
)

_collection_capacity_hash_map := #(
    .key: Type, .value: Type, .policy: Type: HashPolicy#(policy, key)
) (.self: &HashMap#(.key: key, .value: value, .policy: policy)) -> (.count: UIntNative) {
    count = length(&self&._table._slots).count
}

implement#(.key: Type, .value: Type, .policy: Type: HashPolicy#(policy, key)) CollectionCapacity#(
    HashMap#(.key: key, .value: value, .policy: policy)
) (
    .measure_capacity = _collection_capacity_hash_map
)

_hash_invalidate := #(.key: Type, .value: Type, .policy: Type: HashPolicy#(policy, key)) (
    .self : $&HashMap#(.key: key, .value: value, .policy: policy)
) -> () {
    anchor ::= $&self&._shape
    deinit(.self = anchor)
    anchor&= (.marker = 0)
}

_hash_entry := #(.key: Type, .value: Type, .policy: Type: HashPolicy#(policy, key)) (
    .self: &HashMap#(.key: key, .value: value, .policy: policy), .index: UIntNative
) -> (.entry: $&HashMapEntry#(.key: key, .value: value)) {
    if _trusted_dynamic_array_get(.array = &self&._table._slots, .index = index).state != 1 {
        abort
    }

    slot ::= _trusted_uninit_slot#(.t: HashMapEntry#(.key: key, .value: value))(
        .allocation = &self&._table._entries, .index = index
    )
    slot_index: ?UIntNative = ..some(.value = slot._index)
    entry = trusted_establish_allocation_slot#(.t: HashMapEntry#(.key: key, .value: value))(
        .allocation = &self&._table._entries
        .slot       = slot._raw
        .index      = slot_index
        .anchor     = self&._table._entries.anchor
    ).reference
}

_hash_find := #(.key: Type, .value: Type, .policy: Type: HashPolicy#(policy, key)) (
    .self : &HashMap#(.key: key, .value: value, .policy: policy),
    .key  : HashPolicy#(policy, key).Query,
    .hash : UIntNative
) -> (.index: ?UIntNative) {
    count ::= capacity(self).count
    position ::= hash % count
    visited :: UIntNative = 0

    while visited < count {
        slot ::= _trusted_dynamic_array_get(.array = &self&._table._slots, .index = position)
        if slot.state == 0 {
            index = ..none
            return
        }
        if slot.state == 1 and slot.hash == hash {
            entry ::= _hash_entry(self, .index = position).entry
            if HashPolicy#(
                policy, key
            ).equal(
                &self&._policy
                .left  = HashPolicy#(policy, key).query(&self&._policy, .key = &entry&.key)
                .right = key
            ).ok {
                index = ..some(.value = position)
                return
            }
        }
        position = position + 1
        if position == count { position = 0 }
        visited = visited + 1
    }

    index = ..none
}

_hash_vacancy := (.slots: &DynamicArray#(.t: _HashSlot), .hash: UIntNative) -> (
    .index : UIntNative
) {
    count ::= length(slots).count
    index = hash % count
    visited :: UIntNative = 0

    while visited < count {
        if _trusted_dynamic_array_get(.array = slots, .index = index).state != 1 { return }
        index = index + 1
        if index == count { index = 0 }
        visited = visited + 1
    }

    abort
}

_map_reserve_hash_map := #(
    .key      : Type,
    .value    : Type,
    .policy   : Type: HashPolicy#(policy, key),
    .Provider : Type: Allocator#(Provider)
) (
    .self      : $&HashMap#(.key: key, .value: value, .policy: policy),
    .capacity  : UIntNative,
    .allocator : $&Provider
) -> (.result: Errable#(Void, (..out_of_memory))) {
    assume allocator
    old_count ::= capacity(self).count

    if capacity <= old_count {
        result = ..ok Void()
        return
    }
    -- All allocations complete before the first owning relocation. Allocation
    -- failure therefore preserves the old table and its entries. Reacquire loans
    -- after a mutating call because safety summaries conservatively join outcomes.
    slots ::= _hash_slots(.capacity = capacity, .allocator = allocator)!
    entries ::= allocate#(.t: HashMapEntry#(.key: key, .value: value))(
        allocator, .count = capacity
    )!
    index :: UIntNative = 0

    while index < old_count {
        meta ::= _trusted_dynamic_array_get(.array = &self&._table._slots, .index = index)
        if meta.state == 1 {
            destination ::= _hash_vacancy(.slots = &slots, .hash = meta.hash).index
            source_slot ::= _trusted_uninit_slot#(.t: HashMapEntry#(.key: key, .value: value))(
                .allocation = &self&._table._entries, .index = index
            )
            destination_slot ::= _trusted_uninit_slot#(
                .t : HashMapEntry#(.key: key, .value: value)
            )(.allocation = &entries, .index = destination)
            _trusted_uninit_relocate#(.t: HashMapEntry#(.key: key, .value: value))(
                .source_allocation      = &self&._table._entries
                .source                 = source_slot
                .destination_allocation = &entries
                .destination            = destination_slot
            )
            _trusted_dynamic_array_set(
                .array = $&slots
                .index = destination
                .value = _HashSlot(.state = 1, .hash = meta.hash)
            )
        }
        index = index + 1
    }

    deinit(.self = $&self&._table._entries)
    deinit(.self = $&self&._table._slots)
    _hash_invalidate(self)
    -- Replace the table as one ownership unit so its backing roots change
    -- together; independent field replacement retains obsolete sibling facts.
    self&._table = (._entries = ~entries, ._slots = ~slots)

    result = ..ok Void()
}

_map_put_hash_map := #(
    .key      : Type,
    .value    : Type,
    .policy   : Type: HashPolicy#(policy, key),
    .Provider : Type: Allocator#(Provider)
) (
    .self      : $&HashMap#(.key: key, .value: value, .policy: policy),
    .key       : key,
    .value     : value,
    .allocator : $&Provider
) -> (.result: Errable#(Void, (..out_of_memory))) {
    assume allocator
    query ::= HashPolicy#(policy, key).query(&self&._policy, .key = &key)
    digest ::= HashPolicy#(policy, key).hash(&self&._policy, .key = query).hash

    match _hash_find(self, .key = query, .hash = digest).index {
        ..some found {
            slot ::= _trusted_uninit_slot#(.t: HashMapEntry#(.key: key, .value: value))(
                .allocation = &self&._table._entries, .index = found.value
            )
            -- A lexical owner invokes recursive cleanup for structural entries.
            previous ::= _trusted_uninit_take(
                .allocation = $&self&._table._entries, .slot = slot
            )
            entry :: HashMapEntry#(.key: key, .value: value) = (
                .key   = ~key
                .value = ~value
            )
            _trusted_uninit_write(
                .allocation = $&self&._table._entries, .slot = slot, .value = ~entry
            )
            _hash_invalidate(self)
            result = ..ok Void()
            return
        }
        ..none {}
    }

    count ::= capacity(self).count

    if self&._length >= count / 2 {
        grown ::= count * 2
        if grown <= count {
            _hash_discard(.value = ~key, .allocator = allocator)
            _hash_discard(.value = ~value, .allocator = allocator)
            result = ..error(.reason = ..out_of_memory)
            return
        }
        match reserve(self, .capacity = grown, .allocator = allocator) {
            ..ok _ {}
            ..error _ {
                _hash_discard(.value = ~key, .allocator = allocator)
                _hash_discard(.value = ~value, .allocator = allocator)
                result = ..error(.reason = ..out_of_memory)
                return
            }
        }
    }

    index ::= _hash_vacancy(.slots = &self&._table._slots, .hash = digest).index
    slot ::= _trusted_uninit_slot#(.t: HashMapEntry#(.key: key, .value: value))(
        .allocation = &self&._table._entries, .index = index
    )
    entry :: HashMapEntry#(.key: key, .value: value) = (.key = ~key, .value = ~value)
    _trusted_uninit_write(.allocation = $&self&._table._entries, .slot = slot, .value = ~entry)
    _trusted_dynamic_array_set(
        .array = $&self&._table._slots
        .index = index
        .value = _HashSlot(.state = 1, .hash = digest)
    )
    self&._length = self&._length + 1
    _hash_invalidate(self)

    result = ..ok Void()
}

_map_contains_hash_map := #(.key: Type, .value: Type, .policy: Type: HashPolicy#(policy, key)) (
    .self : &HashMap#(.key: key, .value: value, .policy: policy),
    .key  : HashPolicy#(policy, key).Query
) -> (.ok: Bool) {
    digest ::= HashPolicy#(policy, key).hash(&self&._policy, .key = key).hash
    ok = is(.value = _hash_find(self, .key = key, .hash = digest).index, .variant = ..some)
}

_map_get_reference_hash_map := #(
    .key: Type, .value: Type, .policy: Type: HashPolicy#(policy, key)
) (
    .self : &HashMap#(.key: key, .value: value, .policy: policy),
    .key  : HashPolicy#(policy, key).Query
) -> (.result: ?&value) {
    digest ::= HashPolicy#(policy, key).hash(&self&._policy, .key = key).hash

    match _hash_find(self, .key = key, .hash = digest).index {
        ..none { result = ..none }
        ..some found {
            entry ::= _hash_entry(self, .index = found.value).entry
            borrowed ::= depend_on#(.t: &value)(
                .value = &entry&.value
                .on    = erase_reference#(.t: _HashShape)(.base = &self&._shape).reference
            ).result
            result = ..some(.value = borrowed)
        }
    }
}

_map_get_mutable_reference_hash_map := #(
    .key: Type, .value: Type, .policy: Type: HashPolicy#(policy, key)
) (
    .self : $&HashMap#(.key: key, .value: value, .policy: policy),
    .key  : HashPolicy#(policy, key).Query
) -> (.result: ?$&value) {
    digest ::= HashPolicy#(policy, key).hash(&self&._policy, .key = key).hash

    match _hash_find(self, .key = key, .hash = digest).index {
        ..none { result = ..none }
        ..some found {
            entry ::= _hash_entry(self, .index = found.value).entry
            borrowed ::= depend_on#(.t: $&value)(
                .value = $&entry&.value
                .on    = erase_reference#(.t: _HashShape)(.base = &self&._shape).reference
            ).result
            result = ..some(.value = borrowed)
        }
    }
}

_map_extract_hash_map := #(.key: Type, .value: Type, .policy: Type: HashPolicy#(policy, key)) (
    .self : $&HashMap#(.key: key, .value: value, .policy: policy),
    .key  : HashPolicy#(policy, key).Query
) -> (.result: ?HashMapEntry#(.key: key, .value: value)) {
    digest ::= HashPolicy#(policy, key).hash(&self&._policy, .key = key).hash

    match _hash_find(self, .key = key, .hash = digest).index {
        ..none { result = ..none }
        ..some found {
            slot ::= _trusted_uninit_slot#(.t: HashMapEntry#(.key: key, .value: value))(
                .allocation = &self&._table._entries, .index = found.value
            )
            entry ::= _trusted_uninit_take(.allocation = $&self&._table._entries, .slot = slot)
            _trusted_dynamic_array_set(
                .array = $&self&._table._slots
                .index = found.value
                .value = _HashSlot(.state = 2, .hash = 0)
            )
            self&._length = self&._length - 1
            _hash_invalidate(self)
            result = ..some(.value = ~entry)
        }
    }
}

_map_remove_hash_map := #(
    .key      : Type,
    .value    : Type,
    .policy   : Type: HashPolicy#(policy, key),
    .Provider : Type: Allocator#(Provider)
) (
    .self      : $&HashMap#(.key: key, .value: value, .policy: policy),
    .key       : HashPolicy#(policy, key).Query,
    .allocator : $&Provider
) -> (.removed: Bool) {
    assume allocator

    match extract(self, .key = key).result {
        ..none { removed = false }
        ..some ~payload {
            entry ::= ~payload.value
            removed = true
        }
    }
}

implement#(.key: Type, .value: Type, .policy: Type: HashPolicy#(policy, key)) Deinit#(
    HashMap#(.key: key, .value: value, .policy: policy)
) (
    .deinit = (.self: $&HashMap#(.key: key, .value: value, .policy: policy)) -> () {
        index :: UIntNative = 0

        while index < capacity(self).count {
            if [
                _trusted_dynamic_array_get(.array = &self&._table._slots, .index = index).state
                == 1
            ] {
                slot ::= _trusted_uninit_slot#(.t: HashMapEntry#(.key: key, .value: value))(
                    .allocation = &self&._table._entries, .index = index
                )
                entry ::= _trusted_uninit_take(
                    .allocation = $&self&._table._entries, .slot = slot
                )
            }
            index = index + 1
        }

        trusted_opaque_mark_empty(.storage = $&self&._table._entries)
        deinit(.self = $&self&._table._entries)
        deinit(.self = $&self&._table._slots)
        policy ::= ~self&._policy
    }
)

_map_get_hash_map := #(
    .key: Type, .value: Type: ImplicitlyCopyable, .policy: Type: HashPolicy#(policy, key)
) (
    .self : &HashMap#(.key: key, .value: value, .policy: policy),
    .key  : HashPolicy#(policy, key).Query
) -> (.result: ?value) {
    match _map_get_reference_hash_map(self, .key = key).result {
        ..none { result = ..none }
        ..some borrowed { result = ..some(.value = borrowed.value&) }
    }
}
