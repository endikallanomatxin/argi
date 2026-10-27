Owner := (.allocation: Allocation)

implement#(.A: Type: Allocator) Init#(
    Owner, (.allocator: $&A = reach allocator, .length: UIntNative = 4)
) (
    .Result : Type = Errable#(Owner, (..out_of_memory))
    .init   = (.args: (.allocator: $&A = reach allocator, .length: UIntNative = 4)) -> (
        .result : Result
    ) {
        allocation ::= Allocator#(A).allocate(
            .self = args.allocator, .size = args.length, .alignment = 1
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
