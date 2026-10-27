Owner := (.allocation: Allocation)

implement Init#(Owner) (
    .init = #(.A: Type: Allocator) (.allocator: $&A = reach allocator, .length: UIntNative = 4) -> (
        .result : Errable#(Owner, (..out_of_memory))
    ) {
        allocation ::= Allocator#(A).allocate(.self = allocator, .size = length, .alignment = 1)!
        result = ..ok(.allocation = ~allocation)
    }
)

implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () { deinit(.self = $&self&.allocation) }
)

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume allocator := system.page_allocator
    first ::= unwrap_or_abort(Owner(.allocator = allocator, .length = 8))
    second ::= unwrap_or_abort(Owner())
    storage ::= GeneralPurposeAllocator(.allocator = allocator)
    third ::= unwrap_or_abort(Owner(.allocator = $&storage, .length = 16))
}
