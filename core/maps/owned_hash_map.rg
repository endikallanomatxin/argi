-- Consume rejected inputs through ordinary lexical cleanup, which also handles
-- aggregate owners without a nominal destructor.
_owned_hash_discard#(.t: Type)(.value: t, .allocator: $&Allocator) -> () := {
    assume allocator
    discarded ::= ~value
}

-- Ownership-bearing keys are hashed by reference, never copied for lookup.
BorrowedHashPolicy#(.key: Type): Abstract = (
    hash(.self: &Self, .key: &key) -> (.hash: UIntNative)
    eql(.self: &Self, .left: &key, .right: &key) -> (.ok: Bool)
)

StringHashPolicy: Type = ()

StringHashPolicy implements ImplicitlyCopyable
StringHashPolicy implements BorrowedHashPolicy#(.key: String)

hash(.self: &StringHashPolicy, .key: &String) -> (.hash: UIntNative) := {
    text ::= as_view(key)
    hash = string_hash_map_hash(.key = &text).hash
}

eql(.self: &StringHashPolicy, .left: &String, .right: &String) -> (.ok: Bool) := {
    ok = equals(.left = as_view(left), .right = as_view(right)).ok
}

Int32HashPolicy implements BorrowedHashPolicy#(.key: Int32)

hash(.self: &Int32HashPolicy, .key: &Int32) -> (.hash: UIntNative) := {
    remaining :: Int32 = key&
    hash = 0

    if remaining < 0 {
        hash = 2147483648
        remaining = remaining + 2147483647
        remaining = remaining + 1
    }

    bit :: UIntNative = 1

    while remaining > 0 {
        if remaining % 2 != 0 { hash = hash + bit }
        remaining = remaining / 2
        if remaining > 0 { bit = bit * 2 }
    }
}

eql(.self: &Int32HashPolicy, .left: &Int32, .right: &Int32) -> (.ok: Bool) := {
    ok = left&== right&
}

UIntNativeHashPolicy implements BorrowedHashPolicy#(.key: UIntNative)

hash(.self: &UIntNativeHashPolicy, .key: &UIntNative) -> (.hash: UIntNative) := { hash = key&}

eql(.self: &UIntNativeHashPolicy, .left: &UIntNative, .right: &UIntNative) -> (.ok: Bool) := {
    ok = [
        left&
        == right&
    ]
}

OwnedHashMapEntry#(.key: Type, .value: Type): Type = (.key: key, .value: value)

_OwnedHashSlot: Type = (.state: UInt8, .hash: UIntNative)

_OwnedHashSlot implements ImplicitlyCopyable

_OwnedHashTable: Type = (._entries: Allocation, ._slots: DynamicArray#(.t: _OwnedHashSlot))

_OwnedHashShape: Type = (.marker: UInt8 = 0)

_OwnedHashShape deinit(.self: $&_OwnedHashShape) -> () := {}

-- Metadata is always initialized: 0 empty, 1 occupied, 2 deleted. Only occupied
-- indices contain owning entries in the separate allocation. Vacant entry slots
-- are never borrowed, read, or destroyed. Probes are bounded by slot capacity.
OwnedHashMap#(.key: Type, .value: Type, .policy: Type: BorrowedHashPolicy#(.key: key)): Type = (
    ._table  : _OwnedHashTable,
    ._length : UIntNative,
    ._policy : policy,
    ._shape  : _OwnedHashShape
)

_owned_hash_slots(
        .capacity  : UIntNative,
        .allocator : $&Allocator
    ) -> (
        .result : Errable#(DynamicArray#(.t: _OwnedHashSlot), (..out_of_memory))
    ) := {
    slots ::= DynamicArray#(.t: _OwnedHashSlot)(.capacity = capacity, .allocator = allocator)!
    index :: UIntNative = 0

    while index < capacity {
        push_assume_capacity($&slots, .value = _OwnedHashSlot(.state = 0, .hash = 0))
        index = index + 1
    }

    result = ..ok ~slots
}

OwnedHashMap init#(
        .key    : Type,
        .value  : Type,
        .policy : Type: BorrowedHashPolicy#(.key: key)
    )(
        .policy    : policy,
        .allocator : $&Allocator,
        .capacity  : UIntNative   = 8
    ) -> (
        .result : Errable#(
            OwnedHashMap#(.key: key, .value: value, .policy: policy),
            (..out_of_memory)
        )
    ) := {
    constructed :: OwnedHashMap#(.key: key, .value: value, .policy: policy)
    assume allocator
    owned_policy ::= ~policy
    count ::= capacity

    if count < 8 { count = 8 }
    slots ::= _owned_hash_slots(.capacity = count, .allocator = allocator)!
    entries ::= allocate#(.t: OwnedHashMapEntry#(.key: key, .value: value))(
        allocator
        .count = count
    )!
    constructed = (
        ._table  = (._entries = ~entries, ._slots = ~slots)
        ._length = 0
        ._policy = ~owned_policy
        ._shape  = (.marker = 0)
    )

    result = ..ok ~constructed
}

length#(
        .key    : Type,
        .value  : Type,
        .policy : Type: BorrowedHashPolicy#(.key: key)
    )(
        .self : &OwnedHashMap#(.key: key, .value: value, .policy: policy)
    ) -> (
        .count : UIntNative
    ) := { count = self&._length }

capacity#(
        .key    : Type,
        .value  : Type,
        .policy : Type: BorrowedHashPolicy#(.key: key)
    )(
        .self : &OwnedHashMap#(.key: key, .value: value, .policy: policy)
    ) -> (
        .count : UIntNative
    ) := { count = length(&self&._table._slots).count }

_owned_hash_invalidate#(
        .key    : Type,
        .value  : Type,
        .policy : Type: BorrowedHashPolicy#(.key: key)
    )(
        .self : $&OwnedHashMap#(.key: key, .value: value, .policy: policy)
    ) -> () := {
    anchor ::= $&self&._shape
    deinit(.self = anchor)
    anchor&= (.marker = 0)
}

_owned_hash_entry#(
        .key    : Type,
        .value  : Type,
        .policy : Type: BorrowedHashPolicy#(.key: key)
    )(
        .self  : &OwnedHashMap#(.key: key, .value: value, .policy: policy),
        .index : UIntNative
    ) -> (
        .entry : $&OwnedHashMapEntry#(.key: key, .value: value)
    ) := {
    if _trusted_dynamic_array_get(.array = &self&._table._slots, .index = index).state != 1 {
        abort
    }

    slot ::= _trusted_uninit_slot#(.t: OwnedHashMapEntry#(.key: key, .value: value))(
        .allocation = &self&._table._entries
        .index      = index
    )
    entry = trusted_establish_allocation_slot#(.t: OwnedHashMapEntry#(.key: key, .value: value))(
        .allocation = &self&._table._entries
        .slot       = slot._raw
        .anchor     = self&._table._entries.anchor
    ).reference
}

_owned_hash_find#(
        .key    : Type,
        .value  : Type,
        .policy : Type: BorrowedHashPolicy#(.key: key)
    )(
        .self : &OwnedHashMap#(.key: key, .value: value, .policy: policy),
        .key  : &key,
        .hash : UIntNative
    ) -> (
        .index : ?UIntNative
    ) := {
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
            entry ::= _owned_hash_entry(self, .index = position).entry
            if eql(&self&._policy, .left = &entry&.key, .right = key).ok {
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

_owned_hash_vacancy(
        .slots : &DynamicArray#(.t: _OwnedHashSlot),
        .hash  : UIntNative
    ) -> (
        .index : UIntNative
    ) := {
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

reserve#(
        .key    : Type,
        .value  : Type,
        .policy : Type: BorrowedHashPolicy#(.key: key)
    )(
        .self      : $&OwnedHashMap#(.key: key, .value: value, .policy: policy),
        .capacity  : UIntNative,
        .allocator : $&Allocator
    ) -> (
        .result : Errable#(Void, (..out_of_memory))
    ) := {
    assume allocator
    old_count ::= capacity(self).count

    if capacity <= old_count {
        result = ..ok Void()
        return
    }
    -- All allocations complete before the first owning relocation. Allocation
    -- failure therefore preserves the old table and its entries. Reacquire loans
    -- after a mutating call because safety summaries conservatively join outcomes.
    slots ::= _owned_hash_slots(.capacity = capacity, .allocator = allocator)!
    entries ::= allocate#(.t: OwnedHashMapEntry#(.key: key, .value: value))(
        allocator
        .count = capacity
    )!
    index :: UIntNative = 0

    while index < old_count {
        meta ::= _trusted_dynamic_array_get(.array = &self&._table._slots, .index = index)
        if meta.state == 1 {
            destination ::= _owned_hash_vacancy(.slots = &slots, .hash = meta.hash).index
            source_slot ::= _trusted_uninit_slot#(.t: OwnedHashMapEntry#(.key: key, .value: value))(
                .allocation = &self&._table._entries
                .index      = index
            )
            destination_slot ::= _trusted_uninit_slot#(
                .t : OwnedHashMapEntry#(.key: key, .value: value)
            )(.allocation = &entries, .index = destination)
            _trusted_uninit_relocate#(.t: OwnedHashMapEntry#(.key: key, .value: value))(
                .source_allocation      = &self&._table._entries
                .source                 = source_slot
                .destination_allocation = &entries
                .destination            = destination_slot
            )
            _trusted_dynamic_array_set(
                .array = $&slots
                .index = destination
                .value = _OwnedHashSlot(.state = 1, .hash = meta.hash)
            )
        }
        index = index + 1
    }

    deinit(.self = $&self&._table._entries)
    deinit(.self = $&self&._table._slots, .allocator = allocator)
    _owned_hash_invalidate(self)
    -- Replace the table as one ownership unit so its backing roots change
    -- together; independent field replacement retains obsolete sibling facts.
    self&._table = (._entries = ~entries, ._slots = ~slots)

    result = ..ok Void()
}

put#(
        .key    : Type,
        .value  : Type,
        .policy : Type: BorrowedHashPolicy#(.key: key)
    )(
        .self      : $&OwnedHashMap#(.key: key, .value: value, .policy: policy),
        .key       : key,
        .value     : value,
        .allocator : $&Allocator
    ) -> (
        .result : Errable#(Void, (..out_of_memory))
    ) := {
    assume allocator
    digest ::= hash(&self&._policy, .key = &key).hash

    match _owned_hash_find(self, .key = &key, .hash = digest).index {
        ..some found {
            slot ::= _trusted_uninit_slot#(.t: OwnedHashMapEntry#(.key: key, .value: value))(
                .allocation = &self&._table._entries
                .index      = found.value
            )
            -- A lexical owner invokes recursive cleanup for structural entries.
            previous ::= _trusted_uninit_take(.allocation = $&self&._table._entries, .slot = slot)
            entry :: OwnedHashMapEntry#(.key: key, .value: value) = (.key = ~key, .value = ~value)
            _trusted_uninit_write(
                .allocation = $&self&._table._entries
                .slot       = slot
                .value      = ~entry
            )
            _owned_hash_invalidate(self)
            result = ..ok Void()
            return
        }
        ..none {}
    }

    count ::= capacity(self).count

    if self&._length >= count / 2 {
        grown ::= count * 2
        if grown <= count {
            _owned_hash_discard(.value = ~key, .allocator = allocator)
            _owned_hash_discard(.value = ~value, .allocator = allocator)
            result = ..error(.reason = ..out_of_memory)
            return
        }
        match reserve(self, .capacity = grown, .allocator = allocator) {
            ..ok _ {}
            ..error _ {
                _owned_hash_discard(.value = ~key, .allocator = allocator)
                _owned_hash_discard(.value = ~value, .allocator = allocator)
                result = ..error(.reason = ..out_of_memory)
                return
            }
        }
    }

    index ::= _owned_hash_vacancy(.slots = &self&._table._slots, .hash = digest).index
    slot ::= _trusted_uninit_slot#(.t: OwnedHashMapEntry#(.key: key, .value: value))(
        .allocation = &self&._table._entries
        .index      = index
    )
    entry :: OwnedHashMapEntry#(.key: key, .value: value) = (.key = ~key, .value = ~value)
    _trusted_uninit_write(.allocation = $&self&._table._entries, .slot = slot, .value = ~entry)
    _trusted_dynamic_array_set(
        .array = $&self&._table._slots
        .index = index
        .value = _OwnedHashSlot(.state = 1, .hash = digest)
    )
    self&._length = self&._length + 1
    _owned_hash_invalidate(self)

    result = ..ok Void()
}

contains#(
        .key    : Type,
        .value  : Type,
        .policy : Type: BorrowedHashPolicy#(.key: key)
    )(
        .self : &OwnedHashMap#(.key: key, .value: value, .policy: policy),
        .key  : &key
    ) -> (
        .ok : Bool
    ) := {
    digest ::= hash(&self&._policy, .key = key).hash
    ok = is(
        .value   = _owned_hash_find(self, .key = key, .hash = digest).index
        .variant = ..some
    )
}

get_ro_ref#(
        .key    : Type,
        .value  : Type,
        .policy : Type: BorrowedHashPolicy#(.key: key)
    )(
        .self : &OwnedHashMap#(.key: key, .value: value, .policy: policy),
        .key  : &key
    ) -> (
        .result : ?&value
    ) := {
    digest ::= hash(&self&._policy, .key = key).hash

    match _owned_hash_find(self, .key = key, .hash = digest).index {
        ..none { result = ..none }
        ..some found {
            entry ::= _owned_hash_entry(self, .index = found.value).entry
            borrowed ::= depend_on#(.t: &value)(
                .value = &entry&.value
                .on    = erase_reference#(.t: _OwnedHashShape)(.base = &self&._shape).reference
            ).result
            result = ..some(.value = borrowed)
        }
    }
}

extract#(
        .key    : Type,
        .value  : Type,
        .policy : Type: BorrowedHashPolicy#(.key: key)
    )(
        .self : $&OwnedHashMap#(.key: key, .value: value, .policy: policy),
        .key  : &key
    ) -> (
        .result : ?OwnedHashMapEntry#(.key: key, .value: value)
    ) := {
    digest ::= hash(&self&._policy, .key = key).hash

    match _owned_hash_find(self, .key = key, .hash = digest).index {
        ..none { result = ..none }
        ..some found {
            slot ::= _trusted_uninit_slot#(.t: OwnedHashMapEntry#(.key: key, .value: value))(
                .allocation = &self&._table._entries
                .index      = found.value
            )
            entry ::= _trusted_uninit_take(.allocation = $&self&._table._entries, .slot = slot)
            _trusted_dynamic_array_set(
                .array = $&self&._table._slots
                .index = found.value
                .value = _OwnedHashSlot(.state = 2, .hash = 0)
            )
            self&._length = self&._length - 1
            _owned_hash_invalidate(self)
            result = ..some(.value = ~entry)
        }
    }
}

remove#(
        .key    : Type,
        .value  : Type,
        .policy : Type: BorrowedHashPolicy#(.key: key)
    )(
        .self      : $&OwnedHashMap#(.key: key, .value: value, .policy: policy),
        .key       : &key,
        .allocator : $&Allocator
    ) -> (
        .removed : Bool
    ) := {
    assume allocator

    match extract(self, .key = key).result {
        ..none { removed = false }
        ..some ~payload {
            entry ::= ~payload.value
            removed = true
        }
    }
}

OwnedHashMap deinit#(
        .key    : Type,
        .value  : Type,
        .policy : Type: BorrowedHashPolicy#(.key: key)
    )(
        .self      : $&OwnedHashMap#(.key: key, .value: value, .policy: policy),
        .allocator : $&Allocator
    ) -> () := {
    assume allocator
    index :: UIntNative = 0

    while index < capacity(self).count {
        if _trusted_dynamic_array_get(.array = &self&._table._slots, .index = index).state == 1 {
            slot ::= _trusted_uninit_slot#(.t: OwnedHashMapEntry#(.key: key, .value: value))(
                .allocation = &self&._table._entries
                .index      = index
            )
            entry ::= _trusted_uninit_take(.allocation = $&self&._table._entries, .slot = slot)
        }
        index = index + 1
    }

    trusted_opaque_mark_empty(.storage = $&self&._table._entries)
    deinit(.self = $&self&._table._entries)
    deinit(.self = $&self&._table._slots, .allocator = allocator)
    policy ::= ~self&._policy
}
