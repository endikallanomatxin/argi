StringHashMapEntry#(.value: Type): Type = (
    .key   : StringView
    .value : value
    .next  : UIntNative
)

StringHashMapEntry#(.value: Type: ImplicitlyCopyable) implements ImplicitlyCopyable

StringHashMap#(.value: Type): Type = (
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
        .key : &StringView,
    ) -> (
        .view : StringView
    ) := {
    view = key&
}

string_hash_map_key_view(
        .key : &Char,
    ) -> (
        .view : StringView
    ) := {
    view = (
        .data   = trusted_reinterpret_reference#(.from: Char, .to: UInt8)(.base = key).reference
        .length = c_string_length(.text = key).length
    )
}

string_hash_map_key_view(
        .key : &String,
    ) -> (
        .view : StringView
    ) := {
    key_view ::= as_view(key)
    view = key_view
}

-- Builds a native integer from byte bits without pointer casts or depending
-- on implicit integer widening. The loop has exactly eight iterations.
_string_hash_byte_value(.byte: UInt8) -> (.value: UIntNative) := {
    remaining :: UInt8 = byte
    byte_bit :: UInt8 = 128
    native_bit :: UIntNative = 128
    value = 0

    while native_bit > 0 {
        if remaining >= byte_bit {
            remaining = remaining - byte_bit
            value = value + native_bit
        }
        byte_bit = byte_bit / 2
        native_bit = native_bit / 2
    }
}

string_hash_map_hash(
        .key : &StringView,
    ) -> (
        .hash : UIntNative
    ) := {
    -- An order-sensitive polynomial includes every byte. Modulo reduction
    -- bounds each multiply/add below 2^32, including on 32-bit native words:
    -- (16777213 - 1) * 251 + 255 < 2^32. This is not a keyed/adversarial hash.
    modulus :: UIntNative = 16777213
    multiplier :: UIntNative = 251
    hash = 7
    index :: UIntNative = 0

    while index < key&.length {
        byte ::= bytes_get(.view = key, .index = index).byte
        digit ::= _string_hash_byte_value(.byte = byte).value
        hash = hash * multiplier + digit
        hash = hash % modulus
        index = index + 1
    }
}

string_hash_map_bucket_index(
        .bucket_count : UIntNative,
        .key          : &StringView,
    ) -> (
        .index : UIntNative
    ) := {
    if bucket_count == 0 {
        index = 0
        return
    }

    hash ::= string_hash_map_hash(.key = key).hash
    index = hash % bucket_count
}

string_hash_map_prepare_buckets(
        .allocator : $&Allocator,
        .buckets   : $&DynamicArray#(.t: UIntNative),
        .capacity  : UIntNative,
    ) -> () := {
    assume allocator

    buckets&= unwrap_or_abort(
        .value = DynamicArray#(.t: UIntNative)(.allocator = allocator, .capacity = capacity)
    )

    i :: UIntNative = 0

    while i < capacity {
        push_assume_capacity#(.t: UIntNative)(.self = buckets, .value = 0)
        i = i + 1
    }
}

StringHashMap init#(
        .value : Type
    )(
        .allocator : $&Allocator,
        .capacity  : UIntNative   = 8,
    ) -> (
        .result : StringHashMap#(.value: value)
    ) := {
    assume allocator

    bucket_capacity ::= capacity

    if bucket_capacity == 0 {
        bucket_capacity = 1
    }

    result.entries = unwrap_or_abort(
        .value = DynamicArray#(.t: StringHashMapEntry#(.value: value))(
            .allocator = allocator
            .capacity  = bucket_capacity
        )
    )
    string_hash_map_prepare_buckets(
        .allocator = allocator
        .buckets   = $&result.buckets
        .capacity  = bucket_capacity
    )
}

StringHashMap deinit#(
        .value : Type
    )(
        .allocator : $&Allocator,
        .self      : $&StringHashMap#(.value: value),
    ) -> () := {
    assume allocator

    deinit#(.t: UIntNative)(.allocator = allocator, .self = $&self&.buckets)
    deinit#(.t: StringHashMapEntry#(.value: value))(
        .allocator = allocator
        .self      = $&self&.entries
    )
}

string_hash_map_rehash#(
        .value : Type
    )(
        .allocator    : $&Allocator,
        .self         : $&StringHashMap#(.value: value),
        .bucket_count : UIntNative,
    ) -> () := {
    assume allocator

    old_bucket_count ::= length#(.t: UIntNative)(.self = &self&.buckets).count

    if old_bucket_count == bucket_count {
        return
    }

    deinit#(.t: UIntNative)(.allocator = allocator, .self = $&self&.buckets)
    string_hash_map_prepare_buckets(
        .allocator = allocator
        .buckets   = $&self&.buckets
        .capacity  = bucket_count
    )

    i :: UIntNative = 0

    while i < length#(.t: StringHashMapEntry#(.value: value))(.self = &self&.entries).count {
        entry ::= _trusted_dynamic_array_get#(.t: StringHashMapEntry#(.value: value))(
            .array = &self&.entries
            .index = i
        )
        bucket_index ::= string_hash_map_bucket_index(
            .bucket_count = length#(.t: UIntNative)(.self = &self&.buckets).count
            .key          = &entry.key
        ).index
        next ::= _trusted_dynamic_array_get#(.t: UIntNative)(
            .array = &self&.buckets
            .index = bucket_index
        )
        _trusted_dynamic_array_set#(.t: StringHashMapEntry#(.value: value))(
            .array = $&self&.entries
            .index = i
            .value = (
                .key   = entry.key
                .value = entry.value
                .next  = next
            )
        )
        _trusted_dynamic_array_set#(.t: UIntNative)(
            .array = $&self&.buckets
            .index = bucket_index
            .value = [
                i
                + 1
            ]
        )
        i = i + 1
    }
}

string_hash_map_find_entry_index#(
        .value : Type
    )(
        .self : &StringHashMap#(.value: value),
        .key  : &StringView,
    ) -> (
        .index : ?UIntNative
    ) := {
    if length#(.t: UIntNative)(.self = &self&.buckets).count == 0 {
        index = ..none
        return
    }

    bucket_index ::= string_hash_map_bucket_index(
        .bucket_count = length#(.t: UIntNative)(.self = &self&.buckets).count
        .key          = key
    ).index
    current ::= _trusted_dynamic_array_get#(.t: UIntNative)(
        .array = &self&.buckets
        .index = bucket_index
    )

    if current == 0 {
        index = ..none
        return
    }

    current_index ::= current - 1

    while 1 == 1 {
        entry ::= _trusted_dynamic_array_get#(.t: StringHashMapEntry#(.value: value))(
            .array = &self&.entries
            .index = current_index
        )
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

put#(
        .value : Type
    )(
        .allocator : $&Allocator,
        .self      : $&StringHashMap#(.value: value),
        .key       : &StringView,
        .value     : value,
    ) -> () := {
    assume allocator

    found ::= string_hash_map_find_entry_index#(.value: value)(.self = self, .key = key).index

    match found {
        ..some payload {
            entry ::= _trusted_dynamic_array_get#(.t: StringHashMapEntry#(.value: value))(
                .array = &self&.entries
                .index = payload.value
            )
            _trusted_dynamic_array_set#(.t: StringHashMapEntry#(.value: value))(
                .array = $&self&.entries
                .index = payload.value
                .value = (
                    .key   = entry.key
                    .value = value
                    .next  = entry.next
                )
            )
            return
        }
        ..none {
        }
    }

    required_entries ::= [
        length#(.t: StringHashMapEntry#(.value: value))(.self = &self&.entries).count
        + 1
    ]

    if required_entries * 4 >= length#(.t: UIntNative)(.self = &self&.buckets).count * 3 {
        new_bucket_count ::= length#(.t: UIntNative)(.self = &self&.buckets).count * 2
        if new_bucket_count == 0 {
            new_bucket_count = 1
        }
        string_hash_map_rehash#(.value: value)(
            .allocator    = allocator
            .self         = self
            .bucket_count = new_bucket_count
        )
    }

    new_index ::= length#(.t: StringHashMapEntry#(.value: value))(.self = &self&.entries).count
    bucket_index ::= string_hash_map_bucket_index(
        .bucket_count = length#(.t: UIntNative)(.self = &self&.buckets).count
        .key          = key
    ).index
    head ::= _trusted_dynamic_array_get#(.t: UIntNative)(
        .array = &self&.buckets
        .index = bucket_index
    )
    push#(.t: StringHashMapEntry#(.value: value))(
        .allocator = allocator
        .self      = $&self&.entries
        .value     = (
            .key   = key&
            .value = value
            .next  = head
        )
    )
    _trusted_dynamic_array_set#(.t: UIntNative)(
        .array = $&self&.buckets
        .index = bucket_index
        .value = [
            new_index
            + 1
        ]
    )
}

put#(
        .value : Type
    )(
        .allocator : $&Allocator,
        .self      : $&StringHashMap#(.value: value),
        .key       : &Char,
        .value     : value,
    ) -> () := {
    assume allocator

    key_view ::= string_hash_map_key_view(.key = key)
    put#(.value: value)(.allocator = allocator, .self = self, .key = &key_view, .value = value)
}

put#(
        .value : Type
    )(
        .allocator : $&Allocator,
        .self      : $&StringHashMap#(.value: value),
        .key       : &String,
        .value     : value,
    ) -> () := {
    assume allocator

    key_view ::= string_hash_map_key_view(.key = key)
    put#(.value: value)(.allocator = allocator, .self = self, .key = &key_view, .value = value)
}

get#(
        .value : Type
    )(
        .self : &StringHashMap#(.value: value),
        .key  : &StringView,
    ) -> (
        .value : ?value
    ) := {
    found ::= string_hash_map_find_entry_index#(.value: value)(.self = self, .key = key).index

    match found {
        ..some payload {
            entry ::= _trusted_dynamic_array_get#(.t: StringHashMapEntry#(.value: value))(
                .array = &self&.entries
                .index = payload.value
            )
            value = ..some(.value = entry.value)
        }
        ..none {
            value = ..none
        }
    }
}

get#(
        .value : Type
    )(
        .self : &StringHashMap#(.value: value),
        .key  : &Char,
    ) -> (
        .value : ?value
    ) := {
    key_view ::= string_hash_map_key_view(.key = key)
    value = get#(.value: value)(.self = self, .key = &key_view)
}

get#(
        .value : Type
    )(
        .self : &StringHashMap#(.value: value),
        .key  : &String,
    ) -> (
        .value : ?value
    ) := {
    key_view ::= string_hash_map_key_view(.key = key)
    value = get#(.value: value)(.self = self, .key = &key_view)
}

has#(
        .value : Type
    )(
        .self : &StringHashMap#(.value: value),
        .key  : &StringView,
    ) -> (
        .ok : Bool
    ) := {
    found ::= string_hash_map_find_entry_index#(.value: value)(.self = self, .key = key).index
    ok = found ?
}

has#(
        .value : Type
    )(
        .self : &StringHashMap#(.value: value),
        .key  : &Char,
    ) -> (
        .ok : Bool
    ) := {
    key_view ::= string_hash_map_key_view(.key = key)
    ok = has#(.value: value)(.self = self, .key = &key_view)
}

has#(
        .value : Type
    )(
        .self : &StringHashMap#(.value: value),
        .key  : &String,
    ) -> (
        .ok : Bool
    ) := {
    key_view ::= string_hash_map_key_view(.key = key)
    ok = has#(.value: value)(.self = self, .key = &key_view)
}

string_hash_map_retarget_entry_index#(
        .value : Type
    )(
        .self      : $&StringHashMap#(.value: value),
        .entry     : &StringHashMapEntry#(.value: value),
        .old_index : UIntNative,
        .new_index : UIntNative,
    ) -> () := {
    entry_key: StringView = entry&.key
    bucket_index ::= string_hash_map_bucket_index(
        .bucket_count = length#(.t: UIntNative)(.self = &self&.buckets).count
        .key          = &entry_key
    ).index
    target_old ::= old_index + 1
    target_new ::= new_index + 1
    current ::= _trusted_dynamic_array_get#(.t: UIntNative)(
        .array = &self&.buckets
        .index = bucket_index
    )

    if current == target_old {
        _trusted_dynamic_array_set#(.t: UIntNative)(
            .array = $&self&.buckets
            .index = bucket_index
            .value = target_new
        )
        return
    }

    while current != 0 {
        current_index ::= current - 1
        current_entry ::= _trusted_dynamic_array_get#(.t: StringHashMapEntry#(.value: value))(
            .array = &self&.entries
            .index = current_index
        )
        if current_entry.next == target_old {
            _trusted_dynamic_array_set#(.t: StringHashMapEntry#(.value: value))(
                .array = $&self&.entries
                .index = current_index
                .value = (
                    .key   = current_entry.key
                    .value = current_entry.value
                    .next  = target_new
                )
            )
            return
        }
        current = current_entry.next
    }
}

delete#(
        .value : Type
    )(
        .self : $&StringHashMap#(.value: value),
        .key  : &StringView,
    ) -> (
        .value : ?value
    ) := {
    if length#(.t: UIntNative)(.self = &self&.buckets).count == 0 {
        value = ..none
        return
    }

    bucket_index ::= string_hash_map_bucket_index(
        .bucket_count = length#(.t: UIntNative)(.self = &self&.buckets).count
        .key          = key
    ).index
    current ::= _trusted_dynamic_array_get#(.t: UIntNative)(
        .array = &self&.buckets
        .index = bucket_index
    )
    previous :: UIntNative = 0

    while current != 0 {
        current_index ::= current - 1
        entry ::= _trusted_dynamic_array_get#(.t: StringHashMapEntry#(.value: value))(
            .array = &self&.entries
            .index = current_index
        )
        if equals(.left = entry.key, .right = key&).ok {
            if previous == 0 {
                _trusted_dynamic_array_set#(.t: UIntNative)(
                    .array = $&self&.buckets
                    .index = bucket_index
                    .value = entry.next
                )
            } else {
                previous_index ::= previous - 1
                previous_entry ::= _trusted_dynamic_array_get#(
                    .t : StringHashMapEntry#(.value: value)
                )(.array = &self&.entries, .index = previous_index)
                _trusted_dynamic_array_set#(.t: StringHashMapEntry#(.value: value))(
                    .array = $&self&.entries
                    .index = previous_index
                    .value = (
                        .key   = previous_entry.key
                        .value = previous_entry.value
                        .next  = entry.next
                    )
                )
            }

            deleted_value ::= entry.value
            last_index ::= [
                length#(.t: StringHashMapEntry#(.value: value))(.self = &self&.entries).count
                - 1
            ]
            popped ::= pop#(.t: StringHashMapEntry#(.value: value))(.self = $&self&.entries)
            match popped {
                ..ok ~payload {
                    last_entry ::= ~payload
                    if current_index != last_index {
                        _trusted_dynamic_array_set#(.t: StringHashMapEntry#(.value: value))(
                            .array = $&self&.entries
                            .index = current_index
                            .value = ~last_entry
                        )
                        moved_entry ::= _trusted_dynamic_array_get_ro_ref#(
                            .t : StringHashMapEntry#(.value: value)
                        )(.array = &self&.entries, .index = current_index).reference
                        string_hash_map_retarget_entry_index#(.value: value)(
                            .self      = self
                            .entry     = moved_entry
                            .old_index = last_index
                            .new_index = current_index
                        )
                    }
                }
                ..error _ {
                    value = ..none
                    return
                }
            }

            value = ..some(.value = deleted_value)
            return
        }

        previous = current
        current = entry.next
    }

    value = ..none
}

delete#(
        .value : Type
    )(
        .self : $&StringHashMap#(.value: value),
        .key  : &Char,
    ) -> (
        .value : ?value
    ) := {
    key_view ::= string_hash_map_key_view(.key = key)
    value = delete#(.value: value)(.self = self, .key = &key_view)
}

delete#(
        .value : Type
    )(
        .self : $&StringHashMap#(.value: value),
        .key  : &String,
    ) -> (
        .value : ?value
    ) := {
    key_view ::= string_hash_map_key_view(.key = key)
    value = delete#(.value: value)(.self = self, .key = &key_view)
}
