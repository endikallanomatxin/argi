ArenaBlock : Type = (
    .data: $&UInt8
    .size: UIntNative
)

ArenaDomain : Type = (
    .anchor: &Any
)

init(.p: $&ArenaDomain, .anchor: &Any) -> () := {
    p& = (.anchor = anchor)
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
    .backing_allocator: $&CAllocator = #reach allocator, system.allocator,
    .block_size: UIntNative = 4096,
) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    p&.backing_allocator = backing_allocator
    initialized ::= init#(.t: ArenaBlock)(.p = $&p&.blocks, .allocator = backing_allocator, .capacity = 4)
    if is(.value = initialized, .variant = ..error) {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    init(.p = $&p&.domain, .anchor = cast#(.to: &Any)(.value = p))
    p&.block_size = arena_min_block_capacity(.requested = 1, .block_size = block_size).capacity
    p&.current_block_offset = 0
    result = ..ok Void()
}

arena_free_blocks(
    .self: $&ArenaAllocator,
) -> () := {
    i :: UIntNative = 0
    while i < self&.blocks.length {
        block : &ArenaBlock = &self&.blocks[i]
        free(.address = cast#(.to: UIntNative)(.value = block&.data))
        i = i + 1
    }

    self&.blocks.length = 0
    self&.current_block_offset = 0
}

reset(
    .self: $&ArenaAllocator,
) -> () := {
    deinit(.self = $&self&.domain)
    arena_free_blocks(.self = self)
    init(.p = $&self&.domain, .anchor = cast#(.to: &Any)(.value = self))
}

deinit(
    .self: $&ArenaAllocator,
) -> () := {
    deinit(.self = $&self&.domain)
    arena_free_blocks(.self = self)
    deinit(.allocator = self&.backing_allocator, .self = $&self&.blocks)
}

allocate(
    .self: $&ArenaAllocator,
    .size: UIntNative,
) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    required ::= size
    if required == 0 {
        required = 1
    }

    needs_block :: Bool = false
    if self&.blocks.length == 0 {
        needs_block = true
    } else {
        last_block : &ArenaBlock = &self&.blocks[self&.blocks.length - 1]
        if self&.current_block_offset + required > last_block&.size {
            needs_block = true
        }
    }

    if needs_block {
        new_block_size ::= arena_min_block_capacity(.requested = required, .block_size = self&.block_size).capacity
        raw_address ::= malloc(.size = new_block_size).address
        if raw_address == 0 {
            result = ..error(.reason = ..out_of_memory)
            return
        }
        block_data ::= establish_inherited_storage#(.t: UInt8)(
            .address = raw_address,
            -- Physical storage is incorporated into the arena's existing
            -- temporal domain instead of manufacturing a child root.
            .root = cast#(.to: $&Any)(.value = $&self&.domain),
        ).reference
        pushed ::= push(
            .allocator = self&.backing_allocator,
            .self = $&self&.blocks,
            .value = (
                .data = block_data,
                .size = new_block_size,
            ),
        )
        if is(.value = pushed, .variant = ..error) {
            free(.address = raw_address)
            result = ..error(.reason = ..out_of_memory)
            return
        }
        self&.current_block_offset = 0
    }

    active_block : &ArenaBlock = &self&.blocks[self&.blocks.length - 1]
    child_data ::= mutable_reference_offset#(.t: UInt8)(
        .base = active_block&.data,
        .elements = self&.current_block_offset,
    ).reference
    raw ::= raw_pointer#(.t: UInt8)(.address = cast#(.to: UIntNative)(.value = child_data))
    data ::= establish_inherited_reference#(.t: UInt8)(
        .raw = raw,
        -- The domain Place is shared by every child. Reset replaces that
        -- domain without manufacturing a root per child allocation.
        .root = cast#(.to: $&Any)(.value = $&self&.domain),
    ).reference
    deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(.value = self)
    allocation :: Allocation = (
        .data = data,
        .size = size,
        .deallocator = deallocator,
    )
    self&.current_block_offset = self&.current_block_offset + required
    result = ..ok ~allocation
}

deallocate(
    .self: $&ArenaAllocator,
    .data: $&UInt8,
    .size: UIntNative,
) -> () := {
}

ArenaAllocator implements Allocator
ArenaAllocator implements Deallocator
