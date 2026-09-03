StringHashMapEntry#(.value: Type) : Type = (
    .key   : StringView
    .value : value
    .next  : UIntNative
)

StringHashMapEntry#(.value: Type: ImplicitlyCopyable) implements ImplicitlyCopyable

StringHashMap#(.value: Type) : Type = (
    --
    -- Borrowed string-keyed hash map baseline.
    --
    -- Keys are non-owning `StringView`s, so callers must keep the backing text
    -- alive for as long as the map stores the entry.
    --
    -- This baseline intentionally targets copyable values and compiler/runtime
    -- lookup tables. It supports insert/update/get/has/delete and internal
    -- rehashing.
    --
    .buckets : DynamicArray#(.t: UIntNative)
    .entries : DynamicArray#(.t: StringHashMapEntry#(.value: value))
)

string_hash_map_key_view(
    .key: &StringView,
) -> (.view: StringView) := {
    view = key&
}

string_hash_map_key_view(
    .key: &Char,
) -> (.view: StringView) := {
    view = (
        .data = reinterpret_reference#(.from: Char, .to: UInt8)(.base = key).reference,
        .length = c_string_length(.text = key).length,
    )
}

string_hash_map_key_view(
    .key: &String,
) -> (.view: StringView) := {
    key_view ::= as_view(.self = key)
    view = key_view
}

string_hash_map_hash(
    .key: &StringView,
) -> (.hash: UIntNative) := {
    --
    -- Small content hash for the baseline map.
    --
    -- It mixes length plus the first and last byte. This keeps equal keys in
    -- the same bucket without leaning on integer widening paths that are still
    -- rougher than the rest of `core`.
    --
    hash_mul :: UIntNative = 131
    hash_seed :: UIntNative = 7
    hash = key&.length * hash_mul + hash_seed

    if key&.length == 0 {
        return
    }

    first_remaining :: UInt8 = bytes_get(.view = key, .index = 0).byte
    one :: UIntNative = 1
    tail_mul :: UIntNative = 3
    while first_remaining > 0 {
        hash = hash + one
        first_remaining = first_remaining - 1
    }

    if key&.length == 1 {
        return
    }

    last_index ::= key&.length - 1
    last_remaining :: UInt8 = bytes_get(.view = key, .index = last_index).byte
    while last_remaining > 0 {
        hash = hash * tail_mul + one
        last_remaining = last_remaining - 1
    }
}

string_hash_map_bucket_index(
    .bucket_count: UIntNative,
    .key: &StringView,
) -> (.index: UIntNative) := {
    if bucket_count == 0 {
        index = 0
        return
    }

    hash ::= string_hash_map_hash(.key = key).hash
    index = hash % bucket_count
}

string_hash_map_prepare_buckets(
    .allocator: $&Allocator = #reach allocator, system.allocator,
    .buckets: $&DynamicArray#(.t: UIntNative),
    .capacity: UIntNative,
) -> () := {
    init#(.t: UIntNative)(.p = buckets, .allocator = allocator, .capacity = capacity)

    i :: UIntNative = 0
    while i < capacity {
        push_assume_capacity#(.t: UIntNative)(.self = buckets, .value = 0)
        i = i + 1
    }
}

init#(.value: Type) (
    .p: $&StringHashMap#(.value: value),
    .allocator: $&Allocator = #reach allocator, system.allocator,
    .capacity: UIntNative = 8,
) -> () := {
    bucket_capacity ::= capacity
    if bucket_capacity == 0 {
        bucket_capacity = 1
    }

    init#(.t: StringHashMapEntry#(.value: value))(.p = $&p&.entries, .allocator = allocator, .capacity = bucket_capacity)
    string_hash_map_prepare_buckets(.allocator = allocator, .buckets = $&p&.buckets, .capacity = bucket_capacity)
}

deinit#(.value: Type) (
    .allocator: $&Allocator = #reach allocator, system.allocator,
    .self: $&StringHashMap#(.value: value),
) -> () := {
    deinit#(.t: UIntNative)(.allocator = allocator, .self = $&self&.buckets)
    deinit#(.t: StringHashMapEntry#(.value: value))(.allocator = allocator, .self = $&self&.entries)
}

string_hash_map_rehash#(.value: Type) (
    .allocator: $&Allocator = #reach allocator, system.allocator,
    .self: $&StringHashMap#(.value: value),
    .bucket_count: UIntNative,
) -> () := {
    old_bucket_count ::= self&.buckets.length
    if old_bucket_count == bucket_count {
        return
    }

    deinit#(.t: UIntNative)(.allocator = allocator, .self = $&self&.buckets)
    string_hash_map_prepare_buckets(.allocator = allocator, .buckets = $&self&.buckets, .capacity = bucket_count)

    i :: UIntNative = 0
    while i < self&.entries.length {
        entry ::= self&.entries[i]
        bucket_index ::= string_hash_map_bucket_index(.bucket_count = self&.buckets.length, .key = &entry.key).index
        next ::= self&.buckets[bucket_index]
        self&.entries[i] = (
            .key = entry.key,
            .value = entry.value,
            .next = next,
        )
        self&.buckets[bucket_index] = i + 1
        i = i + 1
    }
}

string_hash_map_find_entry_index#(.value: Type) (
    .self: &StringHashMap#(.value: value),
    .key: &StringView,
) -> (.index: ?UIntNative) := {
    if self&.buckets.length == 0 {
        index = ..none
        return
    }

    bucket_index ::= string_hash_map_bucket_index(.bucket_count = self&.buckets.length, .key = key).index
    current ::= self&.buckets[bucket_index]

    if current == 0 {
        index = ..none
        return
    }

    current_index ::= current - 1
    while 1 == 1 {
        entry ::= self&.entries[current_index]
        if equals(.left = entry.key, .right = key&).ok {
            index = ..some(.value = current_index)
            return
        }

        if entry.next == 0 {
            index = ..none
            return
        }

        current_index = entry.next - 1
    }
}

put#(.value: Type) (
    .allocator: $&Allocator = #reach allocator, system.allocator,
    .self: $&StringHashMap#(.value: value),
    .key: &StringView,
    .value: value,
) -> () := {
    found ::= string_hash_map_find_entry_index#(.value: value)(.self = self, .key = key).index
    match found {
        ..some payload {
            entry ::= self&.entries[payload.value]
            self&.entries[payload.value] = (
                .key = entry.key,
                .value = value,
                .next = entry.next,
            )
            return
        }
        ..none {
        }
    }

    required_entries ::= self&.entries.length + 1
    if required_entries * 4 >= self&.buckets.length * 3 {
        new_bucket_count ::= self&.buckets.length * 2
        if new_bucket_count == 0 {
            new_bucket_count = 1
        }
        string_hash_map_rehash#(.value: value)(.allocator = allocator, .self = self, .bucket_count = new_bucket_count)
    }

    new_index ::= self&.entries.length
    bucket_index ::= string_hash_map_bucket_index(.bucket_count = self&.buckets.length, .key = key).index
    head ::= self&.buckets[bucket_index]
    push#(.t: StringHashMapEntry#(.value: value))(
        .allocator = allocator,
        .self = $&self&.entries,
        .value = (
            .key = key&,
            .value = value,
            .next = head,
        ),
    )
    self&.buckets[bucket_index] = new_index + 1
}

put#(.value: Type) (
    .allocator: $&Allocator = #reach allocator, system.allocator,
    .self: $&StringHashMap#(.value: value),
    .key: &Char,
    .value: value,
) -> () := {
    key_view ::= string_hash_map_key_view(.key = key)
    put#(.value: value)(.allocator = allocator, .self = self, .key = &key_view, .value = value)
}

put#(.value: Type) (
    .allocator: $&Allocator = #reach allocator, system.allocator,
    .self: $&StringHashMap#(.value: value),
    .key: &String,
    .value: value,
) -> () := {
    key_view ::= string_hash_map_key_view(.key = key)
    put#(.value: value)(.allocator = allocator, .self = self, .key = &key_view, .value = value)
}

get#(.value: Type) (
    .self: &StringHashMap#(.value: value),
    .key: &StringView,
) -> (.value: ?value) := {
    found ::= string_hash_map_find_entry_index#(.value: value)(.self = self, .key = key).index
    match found {
        ..some payload {
            entry ::= self&.entries[payload.value]
            value = ..some(.value = entry.value)
        }
        ..none {
            value = ..none
        }
    }
}

get#(.value: Type) (
    .self: &StringHashMap#(.value: value),
    .key: &Char,
) -> (.value: ?value) := {
    key_view ::= string_hash_map_key_view(.key = key)
    value = get#(.value: value)(.self = self, .key = &key_view)
}

get#(.value: Type) (
    .self: &StringHashMap#(.value: value),
    .key: &String,
) -> (.value: ?value) := {
    key_view ::= string_hash_map_key_view(.key = key)
    value = get#(.value: value)(.self = self, .key = &key_view)
}

has#(.value: Type) (
    .self: &StringHashMap#(.value: value),
    .key: &StringView,
) -> (.ok: Bool) := {
    found ::= string_hash_map_find_entry_index#(.value: value)(.self = self, .key = key).index
    ok = found?
}

has#(.value: Type) (
    .self: &StringHashMap#(.value: value),
    .key: &Char,
) -> (.ok: Bool) := {
    key_view ::= string_hash_map_key_view(.key = key)
    ok = has#(.value: value)(.self = self, .key = &key_view)
}

has#(.value: Type) (
    .self: &StringHashMap#(.value: value),
    .key: &String,
) -> (.ok: Bool) := {
    key_view ::= string_hash_map_key_view(.key = key)
    ok = has#(.value: value)(.self = self, .key = &key_view)
}

string_hash_map_retarget_entry_index#(.value: Type) (
    .self: $&StringHashMap#(.value: value),
    .entry: &StringHashMapEntry#(.value: value),
    .old_index: UIntNative,
    .new_index: UIntNative,
) -> () := {
    entry_key : StringView = entry&.key
    bucket_index ::= string_hash_map_bucket_index(.bucket_count = self&.buckets.length, .key = &entry_key).index
    target_old ::= old_index + 1
    target_new ::= new_index + 1
    current ::= self&.buckets[bucket_index]

    if current == target_old {
        self&.buckets[bucket_index] = target_new
        return
    }

    while current != 0 {
        current_index ::= current - 1
        current_entry ::= self&.entries[current_index]
        if current_entry.next == target_old {
            self&.entries[current_index] = (
                .key = current_entry.key,
                .value = current_entry.value,
                .next = target_new,
            )
            return
        }
        current = current_entry.next
    }
}

delete#(.value: Type) (
    .self: $&StringHashMap#(.value: value),
    .key: &StringView,
) -> (.value: ?value) := {
    if self&.buckets.length == 0 {
        value = ..none
        return
    }

    bucket_index ::= string_hash_map_bucket_index(.bucket_count = self&.buckets.length, .key = key).index
    current ::= self&.buckets[bucket_index]
    previous :: UIntNative = 0

    while current != 0 {
        current_index ::= current - 1
        entry ::= self&.entries[current_index]
        if equals(.left = entry.key, .right = key&).ok {
            if previous == 0 {
                self&.buckets[bucket_index] = entry.next
            } else {
                previous_index ::= previous - 1
                previous_entry ::= self&.entries[previous_index]
                self&.entries[previous_index] = (
                    .key = previous_entry.key,
                    .value = previous_entry.value,
                    .next = entry.next,
                )
            }

            deleted_value ::= entry.value
            last_index ::= self&.entries.length - 1
            last_entry ::= pop#(.t: StringHashMapEntry#(.value: value))(.self = $&self&.entries)

            if current_index != last_index {
                self&.entries[current_index] = last_entry
                string_hash_map_retarget_entry_index#(.value: value)(
                    .self = self,
                    .entry = &last_entry,
                    .old_index = last_index,
                    .new_index = current_index,
                )
            }

            value = ..some(.value = deleted_value)
            return
        }

        previous = current
        current = entry.next
    }

    value = ..none
}

delete#(.value: Type) (
    .self: $&StringHashMap#(.value: value),
    .key: &Char,
) -> (.value: ?value) := {
    key_view ::= string_hash_map_key_view(.key = key)
    value = delete#(.value: value)(.self = self, .key = &key_view)
}

delete#(.value: Type) (
    .self: $&StringHashMap#(.value: value),
    .key: &String,
) -> (.value: ?value) := {
    key_view ::= string_hash_map_key_view(.key = key)
    value = delete#(.value: value)(.self = self, .key = &key_view)
}
