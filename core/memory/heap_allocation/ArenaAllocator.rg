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

-- The arena's block table is private bookkeeping: relocating this table does
-- not relocate or invalidate any allocation previously returned by the arena.
-- This low-level helper deliberately uses `$&` and must not be exposed as a
-- general DynamicArray operation.
arena_push_block(
    .self: $&DynamicArray#(.t: Allocation),
    .allocator: $&CAllocator,
    .value: Allocation,
) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) #trusted_temporal #raw_boundary := {
    one :: UIntNative = 1
    if self&.length == self&.capacity {
        new_capacity ::= self&.capacity * 2
        if new_capacity == 0 {
            new_capacity = one
        }
        element_size :: UIntNative = size_of(.type = Allocation)
        new_bytes ::= new_capacity * element_size
        allocation_result ::= allocate_fallible(.self = allocator, .size = new_bytes)
        match allocation_result {
            ..ok payload {
                new_data : $&UInt8 = cast#(.to: $&UInt8)(.value = payload)
                if self&.length > 0 {
                    used_bytes ::= self&.length * element_size
                    memcpy_bytes(
                        .dst = array_view#(.t: UInt8)(.data = new_data, .length = used_bytes),
                        .src = array_view#(.t: UInt8)(.data = self&.allocation.data, .length = used_bytes),
                    )
                }
                deallocate(.self = allocator, .data = self&.allocation.data, .size = self&.allocation.size)
                self& = (
                    .allocation = (.data = new_data, .size = new_bytes),
                    .length = self&.length,
                    .capacity = new_capacity,
                )
            }
            ..error _ {
                result = ..error(.reason = ..out_of_memory)
                return
            }
        }
    }

    element_size :: UIntNative = size_of(.type = Allocation)
    address ::= cast#(.to: UIntNative)(.value = self&.allocation.data) + self&.length * element_size
    pointer : $&Allocation = cast#(.to: $&Allocation)(.value = address)
    pointer& = value
    self& = (
        .allocation = self&.allocation,
        .length = self&.length + one,
        .capacity = self&.capacity,
    )
    result = ..ok Void()
}

init(
    .p: $&ArenaAllocator,
    .backing_allocator: $&CAllocator = #reach allocator, system.allocator,
    .block_size: UIntNative = 4096,
) -> () #trusted_temporal := {
    p&.backing_allocator = backing_allocator
    init#(.t: Allocation)(.p = $&p&.blocks, .allocator = backing_allocator, .capacity = 4)
    p&.block_size = arena_min_block_capacity(.requested = 1, .block_size = block_size).capacity
    p&.current_block_offset = 0
}

arena_release_blocks(
    .self: $$&ArenaAllocator,
) -> () #invalidates(self) := {
    i :: UIntNative = 0
    while i < self&.blocks.length {
        block : &Allocation = &self&.blocks[i]
        deallocate(.self = self&.backing_allocator, .data = block&.data, .size = block&.size)
        i = i + 1
    }

    deinit(.allocator = self&.backing_allocator, .self = $$&self&.blocks)
    self&.current_block_offset = 0
}

reset(
    .self: $$&ArenaAllocator,
) -> () #invalidates(self) := {
    backing_allocator ::= self&.backing_allocator
    block_size ::= self&.block_size

    arena_release_blocks(.self = self)
    init#(.t: Allocation)(.p = $&self&.blocks, .allocator = backing_allocator, .capacity = 4)
    self&.block_size = block_size
    self&.backing_allocator = backing_allocator
    self&.current_block_offset = 0
}

deinit(
    .self: $$&ArenaAllocator,
) -> () #invalidates(self) := {
    arena_release_blocks(.self = self)
}

allocate(
    .self: $&ArenaAllocator,
    .size: UIntNative,
) -> (.data: $&UInt8) #returns_follow(data, self) #trusted_temporal := {
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
        block_data ::= allocate(.self = self&.backing_allocator, .size = new_block_size)
        pushed ::= arena_push_block(
            .allocator = self&.backing_allocator,
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
    raw_addr :: UIntNative = cast#(.to: UIntNative)(.value = active_block&.data) + self&.current_block_offset
    self&.current_block_offset = self&.current_block_offset + required
    data = cast#(.to: $&UInt8)(.value = raw_addr)
}

deallocate(
    .self: $&ArenaAllocator,
    .data: $&UInt8,
    .size: UIntNative,
) -> () := {
}

ArenaAllocator implements Allocator
