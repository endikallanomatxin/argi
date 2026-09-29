_ArenaBlock : Type = (
    .storage: Allocation
    .next: UIntNative
    .size: UIntNative
)

-- Replacing the complete domain establishes a new storage generation after
-- reset. Updating only the marker would leave the former generation ended.
ArenaDomain : Type = (.marker: Bool)
init(.p: $&ArenaDomain) -> () := { p& = (.marker = false) }
deinit(.self: $&ArenaDomain) -> () := {}

-- Backing receipts live in block headers. No metadata or storage is acquired
-- until the first allocation; all blocks come from the chosen backing policy.
ArenaAllocator : Type = (
    ._backing_allocator: Virtual#(.abstract: Allocator)
    .domain: ArenaDomain
    ._block_head: UIntNative
    .block_count: UIntNative
    .block_size: UIntNative
    ._current_block_offset: UIntNative
)

init(.p: $&ArenaAllocator, .allocator: $&Allocator, .block_size: UIntNative = 4096) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    p&._backing_allocator = to_virtual#(.abstract: Allocator)(.value = allocator)
    init(.p = $&p&.domain)
    p&._block_head = 0
    p&.block_count = 0
    p&.block_size = block_size
    if p&.block_size == 0 { p&.block_size = 1 }
    p&._current_block_offset = 0
    result = ..ok Void()
}

_trusted_arena_block(.address: UIntNative, .owner: $&ArenaAllocator) -> (.block: $&_ArenaBlock) := {
    raw ::= raw_pointer#(.t: _ArenaBlock)(.address = address).raw
    block = establish_inherited_reference#(.t: _ArenaBlock)(.raw = raw, .root = erase_mutable_reference#(.t: ArenaDomain)(.base = $&owner&.domain).reference).reference
}

arena_free_blocks(.self: $&ArenaAllocator) -> () := {
    while self&._block_head != 0 {
        block ::= _trusted_arena_block(.address = self&._block_head, .owner = self).block
        next ::= block&.next
        storage ::= trusted_opaque_move_out#(.t: Allocation, .storage_type: _ArenaBlock)(.storage = block, .slot = $&block&.storage).result
        self&._block_head = next
        deinit(.self = $&storage)
    }
    self&.block_count = 0
    self&._current_block_offset = 0
}

reset(.self: $&ArenaAllocator) -> () := {
    arena_free_blocks(.self = self)
    deinit(.self = $&self&.domain)
    init(.p = $&self&.domain)
}

deinit(.self: $&ArenaAllocator) -> () := {
    arena_free_blocks(.self = self)
    deinit(.self = $&self&.domain)
}

allocate(.self: $&ArenaAllocator, .size: UIntNative, .alignment: UIntNative) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    _require_allocation_alignment(.alignment = alignment)
    required ::= size
    if required == 0 { required = 1 }
    aligned_offset :: UIntNative = 0
    needs_block :: Bool = true
    if self&._block_head != 0 {
        block ::= _trusted_arena_block(.address = self&._block_head, .owner = self).block
        cursor ::= self&._block_head + self&._current_block_offset
        remainder ::= cursor % alignment
        padding :: UIntNative = 0
        if remainder != 0 { padding = alignment - remainder }
        aligned_offset = self&._current_block_offset + padding
        if aligned_offset >= self&._current_block_offset and aligned_offset <= block&.size {
            if required <= block&.size - aligned_offset { needs_block = false }
        }
    }
    if needs_block {
        header_size ::= size_of(.type = _ArenaBlock)
        minimum ::= header_size + required
        if minimum < required {
            result = ..error(.reason = ..out_of_memory)
            return
        }
        padded ::= minimum + alignment - 1
        if padded < minimum {
            result = ..error(.reason = ..out_of_memory)
            return
        }
        new_size ::= self&.block_size + header_size
        if new_size < header_size { new_size = padded }
        if new_size < padded { new_size = padded }
        block_alignment ::= alignment
        header_alignment ::= alignment_of(.type = _ArenaBlock)
        if block_alignment < header_alignment { block_alignment = header_alignment }
        allocated ::= allocate(.self = $&self&._backing_allocator, .size = new_size, .alignment = block_alignment)
        match allocated {
            ..error _ {
                result = ..error(.reason = ..out_of_memory)
                return
            }
            ..ok ~ payload {
                storage ::= ~payload
                address ::= storage.data.address
                block ::= _trusted_arena_block(.address = address, .owner = self).block
                trusted_opaque_move(.destination = $&block&.storage, .source = ~storage)
                block&.next = self&._block_head
                block&.size = new_size
                self&._block_head = address
                self&.block_count = self&.block_count + 1
                aligned_offset = header_size
                cursor ::= address + header_size
                remainder ::= cursor % alignment
                if remainder != 0 { aligned_offset = header_size + alignment - remainder }
            }
        }
    }
    address ::= self&._block_head + aligned_offset
    deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(.value = self)
    allocation :: Allocation = (
        .data = raw_pointer#(.t: UInt8)(.address = address).raw,
        .size = size,
        .alignment = alignment,
        .anchor = erase_mutable_reference#(.t: ArenaDomain)(.base = $&self&.domain).reference,
        .deallocator = deallocator,
    )
    self&._current_block_offset = aligned_offset + required
    result = ..ok ~allocation
}

deallocate(.self: $&ArenaAllocator, .data: RawPointer#(.t: UInt8), .size: UIntNative, .alignment: UIntNative) -> () := {}
ArenaAllocator implements Allocator
ArenaAllocator implements Deallocator
