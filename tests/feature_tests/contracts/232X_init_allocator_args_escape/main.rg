Owner := (.allocation: Allocation)

implement Init#(Owner) (
    .init = #(.A: Type: Allocator) (.allocator: $&A = reach allocator, .length: UIntNative = 4) -> (
        .result : Errable#(Owner, (..out_of_memory))
    ) {
        allocation ::= Allocator#(A).allocate(
            .self = allocator, .size = length, .alignment = 1
        )!
        result = ..ok(.allocation = ~allocation)
    }
)

implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () { deinit(.self = $&self&.allocation) }
)

escape := (.allocator: $&PageAllocator) -> (.result: Owner) {
    storage ::= GeneralPurposeAllocator(.allocator = allocator)
    result = ~unwrap_or_abort(Owner(.allocator = $&storage))
}

main := (.system: System) -> () { owner ::= escape(system.page_allocator) }
