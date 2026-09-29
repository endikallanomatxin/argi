-- Buckets use two equal-sized backing chunks: metadata in the first and
-- aligned slots in the second. Raw links keep metadata independent of the
-- temporal roots of allocations returned to callers.
_GeneralPurposeBucket : Type = (
    .storage: Allocation
    .anchor: &Any
    .next: UIntNative
    .slot_size: UIntNative
    .search_slot: UIntNative
    .live_count: UIntNative
)

_GeneralPurposeLarge : Type = (
    .metadata: Allocation
    .storage: Allocation
    .anchor: &Any
    .next: UIntNative
    .address: UIntNative
    .size: UIntNative
    .alignment: UIntNative
)

_GeneralPurposeMapped : Type = (
    .address: UIntNative
    .anchor: &Any
)

GeneralPurposeAllocator : Type = (
    ._backing_allocator: Virtual#(.abstract: Allocator)
    ._bucket_size: UIntNative
    ._bucket_head: UIntNative
    ._large_head: UIntNative
)

init(.p: $&GeneralPurposeAllocator, .allocator: $&Allocator) -> () := {
    p&._backing_allocator = to_virtual#(.abstract: Allocator)(.value = allocator)
    p&._bucket_size = 4096
    p&._bucket_head = 0
    p&._large_head = 0
}

-- Only bundled core may turn the allocator's live metadata address into a
-- reference. The backing block stays live until its last slot is released.
_trusted_general_purpose_bucket(.address: UIntNative, .owner: $&GeneralPurposeAllocator) -> (.bucket: $&_GeneralPurposeBucket) := {
    raw ::= raw_pointer#(.t: _GeneralPurposeBucket)(.address = address).raw
    bucket = establish_inherited_reference#(.t: _GeneralPurposeBucket)(.raw = raw, .root = erase_mutable_reference#(.t: GeneralPurposeAllocator)(.base = owner).reference).reference
}

_trusted_general_purpose_large(.address: UIntNative, .owner: $&GeneralPurposeAllocator) -> (.record: $&_GeneralPurposeLarge) := {
    raw ::= raw_pointer#(.t: _GeneralPurposeLarge)(.address = address).raw
    record = establish_inherited_reference#(.t: _GeneralPurposeLarge)(.raw = raw, .root = erase_mutable_reference#(.t: GeneralPurposeAllocator)(.base = owner).reference).reference
}

-- The bitmap follows _GeneralPurposeBucket in the first backing chunk and is
-- initialized explicitly, regardless of the backing allocator's contents.
_trusted_general_purpose_used_word(
    .bucket_address: UIntNative,
    .slot: UIntNative,
    .owner: $&GeneralPurposeAllocator,
) -> (.word: $&UIntNative) := {
    bits_per_word ::= size_of(.type = UIntNative) * 8
    word_index ::= slot / bits_per_word
    address ::= bucket_address + size_of(.type = _GeneralPurposeBucket) + word_index * size_of(.type = UIntNative)
    raw ::= raw_pointer#(.t: UIntNative)(.address = address).raw
    word = establish_inherited_reference#(.t: UIntNative)(.raw = raw, .root = erase_mutable_reference#(.t: GeneralPurposeAllocator)(.base = owner).reference).reference
}

_general_purpose_slot_size(.size: UIntNative, .alignment: UIntNative) -> (.slot_size: UIntNative) := {
    slot_size = size
    if slot_size < alignment { slot_size = alignment }
    if slot_size == 0 { slot_size = 1 }
    rounded :: UIntNative = 1
    while rounded < slot_size {
        if rounded > 9223372036854775807 { return }
        rounded = rounded * 2
    }
    slot_size = rounded
}

_general_purpose_bit(.index: UIntNative) -> (.bit: UIntNative) := {
    bit = 1
    i :: UIntNative = 0
    while i < index {
        bit = bit * 2
        i = i + 1
    }
}

_general_purpose_small_address(
    .self: $&GeneralPurposeAllocator,
    .slot_size: UIntNative,
) -> (.result: Errable#(.t: _GeneralPurposeMapped, .reasons: (..out_of_memory))) := {
    bucket_address :: UIntNative = self&._bucket_head
    while bucket_address != 0 {
        bucket ::= _trusted_general_purpose_bucket(.address = bucket_address, .owner = self).bucket
        slot_count ::= self&._bucket_size / slot_size
        if bucket&.slot_size == slot_size and bucket&.live_count < slot_count {
            -- The cursor never skips a free slot: release lowers it whenever
            -- necessary. The bitmap skips occupied slots after a reused hole.
            slot ::= bucket&.search_slot
            bits_per_word ::= size_of(.type = UIntNative) * 8
            while slot < slot_count {
                bit ::= _general_purpose_bit(.index = slot % bits_per_word).bit
                word ::= _trusted_general_purpose_used_word(.bucket_address = bucket_address, .slot = slot, .owner = self).word
                quotient ::= word& / bit
                if quotient % 2 == 0 {
                    word& = word& + bit
                    bucket&.search_slot = slot + 1
                    bucket&.live_count = bucket&.live_count + 1
                    address ::= bucket_address + self&._bucket_size + slot * slot_size
                    result = ..ok (.address = address, .anchor = bucket&.anchor)
                    return
                }
                slot = slot + 1
            }
            -- A non-full bucket must have a free bit at or after the cursor.
            abort
        }
        bucket_address = bucket&.next
    }

    mapping_size ::= self&._bucket_size * 2
    if mapping_size < self&._bucket_size {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    allocated ::= allocate(.self = $&self&._backing_allocator, .size = mapping_size, .alignment = self&._bucket_size)
    match allocated {
        ..error _ { result = ..error(.reason = ..out_of_memory) }
        ..ok ~ payload {
            backing ::= ~payload
            mapped_address ::= backing.data.address
            anchor ::= backing.anchor
            bucket ::= _trusted_general_purpose_bucket(.address = mapped_address, .owner = self).bucket
            trusted_opaque_move(.destination = $&bucket&.storage, .source = ~backing)
            bucket&.anchor = anchor
            bucket&.next = self&._bucket_head
            bucket&.slot_size = slot_size
            bucket&.search_slot = 1
            bucket&.live_count = 1
            word_count ::= self&._bucket_size / slot_size
            slot :: UIntNative = 0
            while slot < word_count {
                word ::= _trusted_general_purpose_used_word(.bucket_address = mapped_address, .slot = slot, .owner = self).word
                word& = 0
                slot = slot + size_of(.type = UIntNative) * 8
            }
            word ::= _trusted_general_purpose_used_word(.bucket_address = mapped_address, .slot = 0, .owner = self).word
            word& = 1
            self&._bucket_head = mapped_address
            address ::= mapped_address + self&._bucket_size
            result = ..ok (.address = address, .anchor = anchor)
        }
    }
}

_general_purpose_large_address(
    .self: $&GeneralPurposeAllocator,
    .size: UIntNative,
    .alignment: UIntNative,
) -> (.result: Errable#(.t: _GeneralPurposeMapped, .reasons: (..out_of_memory))) := {
    allocated ::= allocate(.self = $&self&._backing_allocator, .size = size, .alignment = alignment)
    match allocated {
        ..error _ { result = ..error(.reason = ..out_of_memory) }
        ..ok ~ payload {
            backing ::= ~payload
            metadata ::= allocate(.self = $&self&._backing_allocator, .size = size_of(.type = _GeneralPurposeLarge), .alignment = alignment_of(.type = _GeneralPurposeLarge))
            match metadata {
                ..error _ {
                    deinit(.self = $&backing)
                    result = ..error(.reason = ..out_of_memory)
                }
                ..ok ~ metadata_payload {
                    record_storage ::= ~metadata_payload
                    record_address ::= record_storage.data.address
                    record ::= _trusted_general_purpose_large(.address = record_address, .owner = self).record
                    address ::= backing.data.address
                    anchor ::= backing.anchor
                    -- Large storage and its metadata retain their own receipts.
                    trusted_opaque_move(.destination = $&record&.storage, .source = ~backing)
                    record&.anchor = anchor
                    record&.next = self&._large_head
                    record&.address = address
                    record&.size = size
                    record&.alignment = alignment
                    trusted_opaque_move(.destination = $&record&.metadata, .source = ~record_storage)
                    self&._large_head = record_address
                    result = ..ok (.address = address, .anchor = anchor)
                }
            }
        }
    }
}

allocate(
    .self: $&GeneralPurposeAllocator,
    .size: UIntNative,
    .alignment: UIntNative,
) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    _require_allocation_alignment(.alignment = alignment)
    slot_size ::= _general_purpose_slot_size(.size = size, .alignment = alignment).slot_size
    mapped :: Errable#(.t: _GeneralPurposeMapped, .reasons: (..out_of_memory))
    if slot_size > self&._bucket_size / 2 {
        mapped = _general_purpose_large_address(.self = self, .size = size, .alignment = alignment)
    } else {
        mapped = _general_purpose_small_address(.self = self, .slot_size = slot_size)
    }
    match mapped {
        ..error _ { result = ..error(.reason = ..out_of_memory) }
        ..ok mapping {
            deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(.value = self)
            allocation ::= establish_allocation_with_anchor(.storage = mapping.address, .size = size, .alignment = alignment, .deallocator = deallocator, .anchor = mapping.anchor)
            result = ..ok ~allocation
        }
    }
}

deallocate(
    .self: $&GeneralPurposeAllocator,
    .data: RawPointer#(.t: UInt8),
    .size: UIntNative,
    .alignment: UIntNative,
) -> () := {
    slot_size ::= _general_purpose_slot_size(.size = size, .alignment = alignment).slot_size
    if slot_size > self&._bucket_size / 2 {
        previous_address :: UIntNative = 0
        record_address :: UIntNative = self&._large_head
        while record_address != 0 {
            record ::= _trusted_general_purpose_large(.address = record_address, .owner = self).record
            if record&.address == data.address {
                if record&.size != size or record&.alignment != alignment { abort }
                next_address ::= record&.next
                if previous_address == 0 {
                    self&._large_head = next_address
                } else {
                    previous ::= _trusted_general_purpose_large(.address = previous_address, .owner = self).record
                    previous&.next = next_address
                }
                storage ::= trusted_opaque_move_out#(.t: Allocation, .storage_type: _GeneralPurposeLarge)(.storage = record, .slot = $&record&.storage).result
                metadata ::= trusted_opaque_move_out#(.t: Allocation, .storage_type: _GeneralPurposeLarge)(.storage = record, .slot = $&record&.metadata).result
                deinit(.self = $&storage)
                deinit(.self = $&metadata)
                return
            }
            previous_address = record_address
            record_address = record&.next
        }
        abort
        return
    }
    previous_address :: UIntNative = 0
    bucket_address :: UIntNative = self&._bucket_head
    while bucket_address != 0 {
        bucket ::= _trusted_general_purpose_bucket(.address = bucket_address, .owner = self).bucket
        data_start ::= bucket_address + self&._bucket_size
        if data.address >= data_start and data.address - data_start < self&._bucket_size {
            if bucket&.slot_size != slot_size { abort }
            offset ::= data.address - data_start
            if offset % slot_size != 0 { abort }
            slot ::= offset / slot_size
            bits_per_word ::= size_of(.type = UIntNative) * 8
            bit ::= _general_purpose_bit(.index = slot % bits_per_word).bit
            word ::= _trusted_general_purpose_used_word(.bucket_address = bucket_address, .slot = slot, .owner = self).word
            quotient ::= word& / bit
            if quotient % 2 == 0 { abort }
            word& = word& - bit
            if slot < bucket&.search_slot { bucket&.search_slot = slot }
            bucket&.live_count = bucket&.live_count - 1
            if bucket&.live_count == 0 {
                next_address ::= bucket&.next
                if previous_address == 0 {
                    self&._bucket_head = next_address
                } else {
                    previous ::= _trusted_general_purpose_bucket(.address = previous_address, .owner = self).bucket
                    previous&.next = next_address
                }
                storage ::= trusted_opaque_move_out#(.t: Allocation, .storage_type: _GeneralPurposeBucket)(.storage = bucket, .slot = $&bucket&.storage).result
                deinit(.self = $&storage)
            }
            return
        }
        previous_address = bucket_address
        bucket_address = bucket&.next
    }
    abort
}

has_live_allocations(.self: &GeneralPurposeAllocator) -> (.has_live: Bool) := {
    has_live = self&._bucket_head != 0 or self&._large_head != 0
}

GeneralPurposeAllocator implements Allocator
GeneralPurposeAllocator implements Deallocator
