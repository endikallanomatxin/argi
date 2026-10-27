ConstructionArgs := #(.Provider: Type) (.allocator: $&Provider, .length: UIntNative)

Construct#(.Target: Type, .Args: Type): Contract = (
    .Result    : Type
    .construct : (.args: Args) -> (.result: Result)
)

Owner := (.allocation: Allocation)

implement#(.A: Type: Allocator) Construct#(Owner, ConstructionArgs#(A)) (
    .Result    : Type = Errable#(Owner, (..out_of_memory))
    .construct = (.args: ConstructionArgs#(A)) -> (.result: Result) {
        allocation ::= Allocator#(
            A
        ).allocate(.self = args.allocator, .size = args.length, .alignment = 1)!
        result = ..ok(.allocation = ~allocation)
    }
)

implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () { deinit(.self = $&self&.allocation) }
)

main := (.system: System) -> (.status_code: Int32 = 0) {
    args :: ConstructionArgs#(PageAllocator) = (
        .allocator = system.page_allocator
        .length    = 4
    )
    owner ::= unwrap_or_abort(
        Construct#(Owner, ConstructionArgs#(PageAllocator)).construct(.args = args)
    )
}
