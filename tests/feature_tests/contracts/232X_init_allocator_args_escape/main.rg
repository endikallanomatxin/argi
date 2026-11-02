Owner := (.allocation: Allocation)

OwnerInitArgs: Type = #(.A: Type: Allocator) (
    .allocator : $&A,
    .length    : UIntNative = 4
)

implement#(.A: Type: Allocator) Init#(Owner, OwnerInitArgs#(A)) (
    .Result : Type = Errable#(Owner, (..out_of_memory))

    .init = OwnerInitArgs#(A) -> (.result: Result) {

        allocation ::= Allocator#(A).allocate(.self = allocator, .size = length, .alignment = 1)!
        result = ..ok(.allocation = ~allocation)
    }
)

implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () { deinit(.self = $&self&.allocation) }
)

escape := (.allocator: $&PageAllocator) -> (.result: Owner) {

    page_virtual ::= to_virtual#(Allocator)(allocator)
    storage ::= GeneralPurposeAllocator(.allocator = page_virtual)
    result = ~unwrap_or_abort(Owner(.allocator = $&storage))
}

main := (.system: System) -> () {

    page :: PageAllocator = PageAllocator(.memory = system.memory)
    owner ::= escape($&page)
}
