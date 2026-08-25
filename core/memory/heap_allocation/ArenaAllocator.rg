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
    .backing_allocator    : Virtual#(.abstract: Allocator)
    .blocks               : DynamicArray#(.t: Allocation)
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
    .backing_allocator: $&Allocator,
    .block_size: UIntNative = 4096,
) -> () := {
    p&.backing_allocator = to_virtual#(.abstract: Allocator)(.value = backing_allocator)
    init#(.t: Allocation)(.p = $&p&.blocks, .allocator = $&p&.backing_allocator, .capacity = 4)
    p&.block_size = arena_min_block_capacity(.requested = 1, .block_size = block_size).capacity
    p&.current_block_offset = 0
}

arena_release_blocks(
    .self: $&ArenaAllocator,
) -> () := {
    i :: UIntNative = 0
    while i < self&.blocks.length {
        block : &Allocation = &self&.blocks[i]
        deallocate(.self = $&self&.backing_allocator, .data = block&.data, .size = block&.size)
        i = i + 1
    }

    deinit(.allocator = $&self&.backing_allocator, .self = $&self&.blocks)
    self&.current_block_offset = 0
}

reset(
    .self: $&ArenaAllocator,
) -> () := {
    block_size ::= self&.block_size

    arena_release_blocks(.self = self)
    init#(.t: Allocation)(.p = $&self&.blocks, .allocator = $&self&.backing_allocator, .capacity = 4)
    self&.block_size = block_size
    self&.current_block_offset = 0
}

deinit(
    .self: $&ArenaAllocator,
) -> () := {
    arena_release_blocks(.self = self)
}

allocate(
    .self: $&ArenaAllocator,
    .size: UIntNative,
) -> (.data: $&UInt8) := {
    required ::= size
    if required == 0 {
        required = 1
    }

    needs_block :: Bool = false
    if self&.blocks.length == 0 {
        needs_block = true
    } else {
        last_block : &Allocation = &self&.blocks[self&.blocks.length - 1]
        if self&.current_block_offset + required > last_block&.size {
            needs_block = true
        }
    }

    if needs_block {
        new_block_size ::= arena_min_block_capacity(.requested = required, .block_size = self&.block_size).capacity
        block_data ::= allocate(.self = $&self&.backing_allocator, .size = new_block_size)
        pushed ::= push(
            .allocator = $&self&.backing_allocator,
            .self = $&self&.blocks,
            .value = (
                .data = block_data,
                .size = new_block_size,
            ),
        )
        if is(.value = pushed, .variant = ..error) {
            zero :: UIntNative = 0
            data = cast#(.to: $&UInt8)(.value = zero)
            return
        }
        self&.current_block_offset = 0
    }

    active_block : &Allocation = &self&.blocks[self&.blocks.length - 1]
    data = mutable_reference_offset#(.t: UInt8)(
        .base = active_block&.data,
        .elements = self&.current_block_offset,
    ).reference
    self&.current_block_offset = self&.current_block_offset + required
}

deallocate(
    .self: $&ArenaAllocator,
    .data: $&UInt8,
    .size: UIntNative,
) -> () := {
}

ArenaAllocator implements Allocator
