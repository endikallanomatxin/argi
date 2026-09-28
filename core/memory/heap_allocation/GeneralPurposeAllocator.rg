-- Buckets use two mapped pages: metadata in the first and aligned slots in
-- the second. The links are raw addresses, so moving metadata does not end
-- the independent temporal roots of allocations returned to callers.
_GeneralPurposeBucket : Type = (
    .next: UIntNative
    .slot_size: UIntNative
    .next_slot: UIntNative
    .live_count: UIntNative
)

_GeneralPurposeLarge : Type = (
    .next: UIntNative
    .address: UIntNative
    .size: UIntNative
    .alignment: UIntNative
)

GeneralPurposeAllocator : Type = (
    .page_size: UIntNative
    .bucket_head: UIntNative
    .large_head: UIntNative
)

init(.p: $&GeneralPurposeAllocator) -> () := {
    p&.page_size = getpagesize().size
    if p&.page_size == 0 { p&.page_size = 4096 }
    p&.bucket_head = 0
    p&.large_head = 0
}

-- Only bundled core may turn the allocator's live metadata address into a
-- reference. The page stays mapped until its last slot is released.
_trusted_general_purpose_bucket(.address: UIntNative, .owner: $&GeneralPurposeAllocator) -> (.bucket: $&_GeneralPurposeBucket) := {
    raw ::= raw_pointer#(.t: _GeneralPurposeBucket)(.address = address).raw
    bucket = establish_inherited_reference#(.t: _GeneralPurposeBucket)(.raw = raw, .root = cast#(.to: &Any)(.value = owner)).reference
}

_trusted_general_purpose_large(.address: UIntNative, .owner: $&GeneralPurposeAllocator) -> (.record: $&_GeneralPurposeLarge) := {
    raw ::= raw_pointer#(.t: _GeneralPurposeLarge)(.address = address).raw
    record = establish_inherited_reference#(.t: _GeneralPurposeLarge)(.raw = raw, .root = cast#(.to: &Any)(.value = owner)).reference
}

-- Anonymous mappings start zero-filled. The bitmap occupies the remainder
-- of the metadata page after _GeneralPurposeBucket.
_trusted_general_purpose_used_word(
    .bucket_address: UIntNative,
    .slot: UIntNative,
    .owner: $&GeneralPurposeAllocator,
) -> (.word: $&UIntNative) := {
    bits_per_word ::= size_of(.type = UIntNative) * 8
    word_index ::= slot / bits_per_word
    address ::= bucket_address + size_of(.type = _GeneralPurposeBucket) + word_index * size_of(.type = UIntNative)
    raw ::= raw_pointer#(.t: UIntNative)(.address = address).raw
    word = establish_inherited_reference#(.t: UIntNative)(.raw = raw, .root = cast#(.to: &Any)(.value = owner)).reference
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
) -> (.result: Errable#(.t: UIntNative, .reasons: (..out_of_memory))) := {
    bucket_address :: UIntNative = self&.bucket_head
    while bucket_address != 0 {
        bucket ::= _trusted_general_purpose_bucket(.address = bucket_address, .owner = self).bucket
        if bucket&.slot_size == slot_size and bucket&.next_slot < self&.page_size / slot_size {
            slot ::= bucket&.next_slot
            bits_per_word ::= size_of(.type = UIntNative) * 8
            bit ::= _general_purpose_bit(.index = slot % bits_per_word).bit
            word ::= _trusted_general_purpose_used_word(.bucket_address = bucket_address, .slot = slot, .owner = self).word
            word& = word& + bit
            bucket&.next_slot = slot + 1
            bucket&.live_count = bucket&.live_count + 1
            address ::= bucket_address + self&.page_size + slot * slot_size
            result = ..ok address
            return
        }
        bucket_address = bucket&.next
    }

    mapping_size ::= self&.page_size * 2
    if mapping_size < self&.page_size {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    mapped_address ::= _page_allocator_map_anonymous(.length = mapping_size).address
    if mapped_address + 1 == 0 {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    bucket ::= _trusted_general_purpose_bucket(.address = mapped_address, .owner = self).bucket
    one :: UIntNative = 1
    bucket& = (.next = self&.bucket_head, .slot_size = slot_size, .next_slot = one, .live_count = one)
    word ::= _trusted_general_purpose_used_word(.bucket_address = mapped_address, .slot = 0, .owner = self).word
    word& = one
    self&.bucket_head = mapped_address
    address ::= mapped_address + self&.page_size
    result = ..ok address
}

_general_purpose_large_address(
    .self: $&GeneralPurposeAllocator,
    .size: UIntNative,
    .alignment: UIntNative,
) -> (.result: Errable#(.t: UIntNative, .reasons: (..out_of_memory))) := {
    mapped ::= _page_allocator_map_aligned(.size = size, .alignment = alignment, .page_size = self&.page_size)
    match mapped {
        ..error _ { result = ..error(.reason = ..out_of_memory) }
        ..ok address {
            record_address ::= _page_allocator_map_anonymous(.length = self&.page_size).address
            if record_address + 1 == 0 {
                mapped_size ::= page_allocator_round_up(.size = size, .alignment = self&.page_size).rounded
                if munmap(.address = address, .length = mapped_size).status != 0 { abort }
                result = ..error(.reason = ..out_of_memory)
                return
            }
            record ::= _trusted_general_purpose_large(.address = record_address, .owner = self).record
            record& = (.next = self&.large_head, .address = address, .size = size, .alignment = alignment)
            self&.large_head = record_address
            result = ..ok address
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
    mapped :: Errable#(.t: UIntNative, .reasons: (..out_of_memory))
    if slot_size > self&.page_size / 2 {
        mapped = _general_purpose_large_address(.self = self, .size = size, .alignment = alignment)
    } else {
        mapped = _general_purpose_small_address(.self = self, .slot_size = slot_size)
    }
    match mapped {
        ..error _ { result = ..error(.reason = ..out_of_memory) }
        ..ok address {
            deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(.value = self)
            allocation ::= establish_allocation(.storage = address, .size = size, .alignment = alignment, .deallocator = deallocator)
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
    if slot_size > self&.page_size / 2 {
        previous_address :: UIntNative = 0
        record_address :: UIntNative = self&.large_head
        while record_address != 0 {
            record ::= _trusted_general_purpose_large(.address = record_address, .owner = self).record
            if record&.address == data.address {
                if record&.size != size or record&.alignment != alignment { abort }
                next_address ::= record&.next
                if previous_address == 0 {
                    self&.large_head = next_address
                } else {
                    previous ::= _trusted_general_purpose_large(.address = previous_address, .owner = self).record
                    previous&.next = next_address
                }
                mapped_size ::= page_allocator_round_up(.size = size, .alignment = self&.page_size).rounded
                if munmap(.address = data.address, .length = mapped_size).status != 0 { abort }
                if munmap(.address = record_address, .length = self&.page_size).status != 0 { abort }
                return
            }
            previous_address = record_address
            record_address = record&.next
        }
        abort
        return
    }
    previous_address :: UIntNative = 0
    bucket_address :: UIntNative = self&.bucket_head
    while bucket_address != 0 {
        bucket ::= _trusted_general_purpose_bucket(.address = bucket_address, .owner = self).bucket
        data_start ::= bucket_address + self&.page_size
        if data.address >= data_start and data.address - data_start < self&.page_size {
            if bucket&.slot_size != slot_size { abort }
            offset ::= data.address - data_start
            if offset % slot_size != 0 { abort }
            slot ::= offset / slot_size
            if slot >= bucket&.next_slot { abort }
            bits_per_word ::= size_of(.type = UIntNative) * 8
            bit ::= _general_purpose_bit(.index = slot % bits_per_word).bit
            word ::= _trusted_general_purpose_used_word(.bucket_address = bucket_address, .slot = slot, .owner = self).word
            quotient ::= word& / bit
            if quotient % 2 == 0 { abort }
            word& = word& - bit
            bucket&.live_count = bucket&.live_count - 1
            if bucket&.live_count == 0 {
                next_address ::= bucket&.next
                if previous_address == 0 {
                    self&.bucket_head = next_address
                } else {
                    previous ::= _trusted_general_purpose_bucket(.address = previous_address, .owner = self).bucket
                    previous&.next = next_address
                }
                if munmap(.address = bucket_address, .length = self&.page_size * 2).status != 0 { abort }
            }
            return
        }
        previous_address = bucket_address
        bucket_address = bucket&.next
    }
    abort
}

has_live_allocations(.self: &GeneralPurposeAllocator) -> (.has_live: Bool) := {
    has_live = self&.bucket_head != 0 or self&.large_head != 0
}

GeneralPurposeAllocator implements Allocator
GeneralPurposeAllocator implements Deallocator
