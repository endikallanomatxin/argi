-- A fixed-size owning bit set. Mutable borrowed views retain the backing
-- dynamic array's storage and shape, and therefore cannot outlive cleanup.
BitSet: Type = (._storage: DynamicArray#(.t: UInt8), ._count: UIntNative)

BitSet init(
        .count     : UIntNative,
        .allocator : $&Allocator
    ) -> (
        .result : Errable#(.t: BitSet, .reasons: (..out_of_memory))
    ) := {
    assume allocator
    needed ::= count / 8
    if count % 8 != 0 { needed = needed + 1 }
    storage ::= DynamicArray#(.t: UInt8)(.allocator = allocator, .capacity = needed)!
    index :: UIntNative = 0
    while index < needed {
        push_assume_capacity(.self = $&storage, .value = 0)
        index = index + 1
    }
    result = ..ok(._storage = ~storage, ._count = count)
}

BitSet deinit(.self: $&BitSet, .allocator: $&Allocator) -> () := {
    assume allocator
    deinit(.self = $&self&._storage, .allocator = allocator)
}

length(.self: &BitSet) -> (.count: UIntNative) := { count = self&._count }

as_view(.self: $&BitSet) -> (.view: BitSetView) := {
    view = (._bytes = array_view(.array = $&self&._storage).view, ._count = self&._count)
}

contains(
        .self  : &BitSet,
        .index : UIntNative
    ) -> (
        .result : Errable#(.t: Bool, .reasons: (..out_of_bounds))
    ) := {
    if index >= self&._count {
        result = ..error(.reason = ..out_of_bounds)
        return
    }
    byte ::= unwrap_or_abort(.value = get_ro_ref(.self = &self&._storage, .index = index / 8))
    mask ::= _bit_set_mask(.index = index).mask
    result = ..ok byte&/ mask % 2 != 0
}

set(
        .self  : $&BitSet,
        .index : UIntNative,
        .value : Bool        = true
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..out_of_bounds))
    ) := {
    view ::= as_view(.self = self).view
    result = set(.self = $&view, .index = index, .value = value)
}

count_set(.self: &BitSet) -> (.count: UIntNative) := {
    count = _bit_set_count(
        .bytes  = array_view_ro(.array = &self&._storage).view
        .extent = self&._count
    ).count
}
