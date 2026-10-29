-- Heap storage needs no region lifetime beyond its own root. This initialized
-- marker gives the uniform anchor field a stable lifetime without making the
-- allocator object a shared validity root for unrelated allocations.
allocation_static_anchor :: UInt8 = 0

-- Logical extent retained by typed allocation requests. This describes slots,
-- never their occupancy, initialization or cleanup obligations.
_AllocationSlotExtent := (.element_size: UIntNative, .count: UIntNative)

Allocation := (
    --
    -- Contiguous allocated storage together with the deallocator required for
    -- its physical cleanup.
    --
    -- The concrete allocate operation determines its temporal facts. A heap
    -- allocation can own a fresh root, while region-backed storage can depend
    -- on a shared root without owning an individual one.
    --
    -- The nominal type does not imply ownership, element type, shape, or view
    -- semantics.
    --
    -- `Allocation` is move-only. A higher-level owner may provide its own
    -- explicit `copy()` that acquires independent storage.
    --
    .data      : RawPointer#(.t: UInt8)
    .size      : UIntNative
    .alignment : UIntNative
    -- The heap uses a static marker; arena children point at ArenaDomain.
    .anchor      : &Any
    .deallocator : Virtual#(.contract: Deallocator)
    -- Allocator-authenticated bounds. Public receipt fields can restrict a
    -- request, but cannot enlarge this region or change the address, size,
    -- or alignment passed to physical cleanup.
    ._storage_address   : UIntNative
    ._storage_size      : UIntNative
    ._storage_alignment : UIntNative
    -- A granted prefix may be smaller than the acquisition being released.
    ._release_size : UIntNative
    ._slot_extent  : ?_AllocationSlotExtent
    ._slot_state   : UIntNative             = 0
)

-- Compiler-owned temporal boundary used after a physical allocator has
-- returned backing storage. Each allocation owns a fresh temporal root.
-- Region-backed storage also retains the generation of its backing anchor.
-- The allocator certifies acquisition and containment; these scalar arguments
-- are not themselves evidence that storage was acquired. Private bounds keep
-- that assertion intact when the receipt crosses ordinary caller code.
trusted_establish_allocation := (
    .storage     : UIntNative,
    .size        : UIntNative,
    .alignment   : UIntNative,
    .deallocator : Virtual#(.contract: Deallocator),
    .anchor      : &Any        = erase_reference#(.t: UInt8)(
        .base = &allocation_static_anchor
    ).reference,
) -> (.allocation: Allocation) {
    _require_allocation_alignment(.alignment = alignment)

    if storage == 0 and size != 0 { abort }
    if storage % alignment != 0 { abort }
    if storage + size < storage { abort }
    allocation = (
        .data               = raw_pointer#(.t: UInt8)(.address = storage).raw
        .size               = size
        .alignment          = alignment
        .anchor             = anchor
        .deallocator        = deallocator
        ._storage_address   = storage
        ._storage_size      = size
        ._storage_alignment = alignment
        ._release_size      = size
        ._slot_extent       = ..none
    )
}

-- Normal establishment requires an acquisition receipt. Its private bounds
-- remain authoritative while forwarding moves the receipt. Establishment
-- consumes that receipt through the ordinary move rules.
establish_allocation := (
    .storage     : AcquiredStorage,
    .size        : UIntNative,
    .alignment   : UIntNative,
    .deallocator : Virtual#(.contract: Deallocator),
    .anchor      : &Any             = erase_reference#(.t: UInt8)(
        .base = &allocation_static_anchor
    ).reference,
) -> (.allocation: Allocation) {
    _require_allocation_alignment(.alignment = alignment)

    if size > storage._size { abort }
    if storage._address % alignment != 0 { abort }
    allocation = trusted_establish_allocation(
        .storage     = storage._address
        .size        = size
        .alignment   = alignment
        .deallocator = deallocator
        .anchor      = anchor
    ).allocation
    allocation._release_size = storage._size
    allocation._storage_alignment = storage._alignment
}

implement Deinit#(Allocation) (
    .deinit = (.self: $&Allocation) -> () {
        -- Cleanup may touch backing metadata; an ended region cannot be released.
        live ::= self&.anchor&
        data ::= raw_pointer#(.t: UInt8)(.address = self&._storage_address).raw
        Deallocator#(
        ).deallocate(
            $&self&.deallocator
            .data      = data
            .size      = self&._release_size
            .alignment = self&._storage_alignment
        )
    }
)

-- Shared across element types. Forward failures intact instead of capturing
-- another tracer context while attaching metadata to successful receipts.
_typed_allocation_result := (
    .allocated    : Errable#(Allocation, (..out_of_memory)),
    .element_size : UIntNative,
    .count        : UIntNative,
    .prefix       : UIntNative,
    .payload_size : UIntNative,
    .error_tracer : $&Virtual#(ErrorTracer)
) -> (.result: Errable#(Allocation, (..out_of_memory))) {
    assume error_tracer

    match allocated {
        ..ok ~payload {
            allocation ::= ~payload
            allocation._slot_extent = ..some(
                .value = _AllocationSlotExtent(.element_size = element_size, .count = count)
            )
            allocation.data.address = allocation.data.address + prefix
            allocation.size = payload_size
            result = ..ok ~allocation
        }
        ..error ~failure { result = ..error ~failure }
    }
}
