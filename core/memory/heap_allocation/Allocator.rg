..out_of_memory

Allocator#(.Provider: Type): Contract = (
    .allocate : (.self: $&Provider, .size: UIntNative, .alignment: UIntNative) -> (
        .result : Errable#(Allocation, (..out_of_memory))
    ) where {
        on result ..ok {
            owns(result)
            depends_on(result, self, size, alignment)
        }
        on result ..error { depends_on(result, error_tracer) }
    }
)

-- Byte requests and typed element requests share selected allocator evidence.
allocate_bytes#(.SelfType: Type: Allocator#(SelfType)) := (
    .self: $&SelfType, .size: UIntNative, .alignment: UIntNative = 1
) -> (.result: Errable#(Allocation, (..out_of_memory))) {
    result = Allocator#().allocate(self, .size = size, .alignment = alignment)
}

allocate#(.t: Type, .SelfType: Type: Allocator#(SelfType)) := (
    .self: $&SelfType, .count: UIntNative = 1
) -> (.result: Errable#(Allocation, (..out_of_memory))) {
    element_size ::= size_of(.type = t)
    bytes ::= element_size * count
    if element_size != 0 and bytes / element_size != count {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    result = Allocator#().allocate(self, .size = bytes, .alignment = alignment_of(.type = t))
}
