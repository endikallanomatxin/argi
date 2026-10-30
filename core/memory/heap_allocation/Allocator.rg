..out_of_memory

Allocator#(.Provider: Type): Contract = (
    .allocate : (.self: $&Provider, .size: UIntNative, .alignment: UIntNative) -> (
        .result : Errable#(Allocation, (..out_of_memory))
    ) where {
        on result ..ok {
            owns(result)
            depends_on(result, self, size, alignment)
        }
        on result ..error {}

    }
)

-- Byte requests and typed element requests share selected allocator evidence.
allocate_bytes := #(.SelfType: Type: Allocator#(SelfType)) (
    .self: $&SelfType, .size: UIntNative, .alignment: UIntNative = 1
) -> (.result: Errable#(Allocation, (..out_of_memory))) {

    result = Allocator#().allocate(self, .size = size, .alignment = alignment)
}

-- Validate the complete typed reservation before calling the provider, including
-- element bytes and companion metadata. Containers need only check their shape.
allocate := #(.t: Type, .SelfType: Type: Allocator#(SelfType)) (
    .self: $&SelfType, .count: UIntNative = 1
) -> (.result: Errable#(Allocation, (..out_of_memory))) {

    element_size ::= size_of(.type = t)
    bytes ::= element_size * count
    if element_size != 0 and bytes / element_size != count {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    metadata ::= _allocation_metadata_layout#(.t: t)().layout
    flags ::= metadata.cleanup_flags * count
    leaves ::= metadata.reference_leaves * count
    reference_bytes ::= leaves * metadata.reference_bytes
    if [
        count != 0
        and [
            flags / count != metadata.cleanup_flags
            or leaves / count != metadata.reference_leaves
        ]
    ] {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    if leaves != 0 and reference_bytes / leaves != metadata.reference_bytes {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    prefix ::= flags
    remainder ::= prefix % metadata.alignment
    if remainder != 0 {
        prefix = prefix + metadata.alignment - remainder
        if prefix < flags {
            result = ..error(.reason = ..out_of_memory)
            return
        }
    }
    prefix = prefix + reference_bytes
    if prefix < reference_bytes {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    if prefix != 0 {
        previous ::= prefix
        prefix = prefix + metadata.header_bytes
        if prefix < previous {
            result = ..error(.reason = ..out_of_memory)
            return
        }
    }
    alignment ::= alignment_of(.type = t)
    remainder = prefix % alignment
    if remainder != 0 {
        previous ::= prefix
        prefix = prefix + alignment - remainder
        if prefix < previous {
            result = ..error(.reason = ..out_of_memory)
            return
        }
    }
    total ::= prefix + bytes
    if total < prefix {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    if prefix != 0 and alignment < metadata.alignment { alignment = metadata.alignment }
    allocated ::= Allocator#().allocate(self, .size = total, .alignment = alignment)
    tagged ::= _typed_allocation_result(
        .allocated    = ~allocated
        .element_size = element_size
        .count        = count
        .prefix       = prefix
        .payload_size = bytes
    )
    match tagged {
        ..error ~failure { result = ..error ~failure }
        ..ok ~allocation {
            if prefix != 0 {
                allocation._slot_state = _prepare_allocation_metadata#(.t: t)(
                    .allocation = &allocation
                ).state
            }
            result = ..ok ~allocation
        }
    }
}
