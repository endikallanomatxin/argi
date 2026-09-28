ArenaBlock : Type = (
    .data: RawPointer#(.t: UInt8)
    .size: UIntNative
)

-- Structural temporal anchor. Its identity is the `ArenaAllocator.domain`
-- Place, so it deliberately carries no reference back to its owner. The
-- marker is retained because empty values currently require an `init` path
-- that cannot initialize itself without a recursive resolution cycle.
ArenaDomain : Type = (
    .marker: Bool
)

init(.p: $&ArenaDomain) -> () := {
    p& = (.marker = false)
}

deinit(.self: $&ArenaDomain) -> () := {
}

ArenaAllocator : Type = (
    --
    -- Simple bump arena backed by another allocator.
    --
    -- Individual `deallocate()` calls are ignored. Memory is reclaimed only by
    -- `reset()` or `deinit()`.
    --
    -- This baseline intentionally targets copyable payloads and compiler-style
    -- scratch allocations, not long-lived fine-grained ownership.
    --
    .backing_allocator    : $&CAllocator
    .blocks               : DynamicArray#(.t: ArenaBlock)
    .domain               : ArenaDomain
    .block_size           : UIntNative
    .current_block_offset : UIntNative
)

arena_min_block_capacity(
    .requested: UIntNative,
    .block_size: UIntNative,
) -> (.capacity: UIntNative) := {
    capacity = block_size
    if capacity == 0 {
        capacity = 1
    }
    if capacity < requested {
        capacity = requested
    }
}

init(
    .p: $&ArenaAllocator,
    .backing_allocator: $&CAllocator,
    .block_size: UIntNative = 4096,
) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    assume backing_allocator

    p&.backing_allocator = backing_allocator
    initialized ::= init#(.t: ArenaBlock)(.p = $&p&.blocks, .allocator = backing_allocator, .capacity = 4)
    if is(.value = initialized, .variant = ..error) {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    init(.p = $&p&.domain)
    p&.block_size = arena_min_block_capacity(.requested = 1, .block_size = block_size).capacity
    p&.current_block_offset = 0
    result = ..ok Void()
}

arena_free_blocks(
    .self: $&ArenaAllocator,
) -> () := {
    while length#(.t: ArenaBlock)(.self = &self&.blocks).count != 0 {
        removed ::= pop#(.t: ArenaBlock)(.self = $&self&.blocks)
        match removed {
            ..ok ~ block {
                free(.address = block.data.address)
            }
            ..error _ { abort }
        }
    }

    _trusted_dynamic_array_mark_empty#(.t: ArenaBlock)(.self = $&self&.blocks)
    self&.current_block_offset = 0
}

reset(
    .self: $&ArenaAllocator,
) -> () := {
    arena_free_blocks(.self = self)
    deinit(.self = $&self&.domain)
    init(.p = $&self&.domain)
    _trusted_dynamic_array_mark_empty#(.t: ArenaBlock)(.self = $&self&.blocks)
}

deinit(
    .self: $&ArenaAllocator,
) -> () := {
    arena_free_blocks(.self = self)
    deinit(.self = $&self&.domain)
    deinit(.allocator = self&.backing_allocator, .self = $&self&.blocks)
}

allocate(
    .self: $&ArenaAllocator,
    .size: UIntNative,
    .alignment: UIntNative,
) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    if alignment == 0 {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    required ::= size
    if required == 0 {
        required = 1
    }

    aligned_offset :: UIntNative = 0
    needs_block :: Bool = false
    if length#(.t: ArenaBlock)(.self = &self&.blocks).count == 0 {
        needs_block = true
    } else {
        last_block : &ArenaBlock = _trusted_dynamic_array_get_ro_ref#(.t: ArenaBlock)(.array = &self&.blocks, .index = length#(.t: ArenaBlock)(.self = &self&.blocks).count - 1).reference
        base ::= last_block&.data.address
        cursor ::= base + self&.current_block_offset
        remainder ::= cursor % alignment
        padding :: UIntNative = 0
        if remainder != 0 { padding = alignment - remainder }
        aligned_offset = self&.current_block_offset + padding
        if cursor < base or aligned_offset < self&.current_block_offset or aligned_offset > last_block&.size or required > last_block&.size - aligned_offset {
            needs_block = true
        }
    }

    if needs_block {
        minimum_size ::= required + alignment - 1
        if minimum_size < required {
            result = ..error(.reason = ..out_of_memory)
            return
        }
        new_block_size ::= arena_min_block_capacity(.requested = minimum_size, .block_size = self&.block_size).capacity
        metadata_ready ::= ensure_capacity#(.t: ArenaBlock)(
            .allocator = self&.backing_allocator,
            .self = $&self&.blocks,
            .capacity = length#(.t: ArenaBlock)(.self = &self&.blocks).count + 1,
        )
        if is(.value = metadata_ready, .variant = ..error) {
            result = ..error(.reason = ..out_of_memory)
            return
        }
        raw_address ::= malloc(.size = new_block_size).address
        if raw_address == 0 {
            result = ..error(.reason = ..out_of_memory)
            return
        }
        block_storage ::= establish_inherited_storage(
            .address = raw_address,
            -- Physical storage is incorporated into the arena's existing
            -- temporal domain instead of manufacturing a child root.
            .root = cast#(.to: $&Any)(.value = $&self&.domain),
        ).raw
        -- Metadata capacity was secured before acquiring physical storage, so
        -- publishing this block has no later fallible rollback path.
        push_assume_capacity#(.t: ArenaBlock)(
            .self = $&self&.blocks,
            .value = (
                .data = block_storage,
                .size = new_block_size,
            ),
        )
        self&.current_block_offset = 0
        remainder ::= raw_address % alignment
        if remainder != 0 { aligned_offset = alignment - remainder }
    }

    active_block : &ArenaBlock = _trusted_dynamic_array_get_ro_ref#(.t: ArenaBlock)(.array = &self&.blocks, .index = length#(.t: ArenaBlock)(.self = &self&.blocks).count - 1).reference
    address ::= active_block&.data.address + aligned_offset
    deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(.value = self)
    allocation :: Allocation = (
        .data = raw_pointer#(.t: UInt8)(.address = address).raw,
        .size = size,
        .alignment = alignment,
        .anchor = cast#(.to: &Any)(.value = $&self&.domain),
        .deallocator = deallocator,
    )
    self&.current_block_offset = aligned_offset + required
    result = ..ok ~allocation
}

deallocate(
    .self: $&ArenaAllocator,
    .data: RawPointer#(.t: UInt8),
    .size: UIntNative,
    .alignment: UIntNative,
) -> () := {
}

ArenaAllocator implements Allocator
ArenaAllocator implements Deallocator
