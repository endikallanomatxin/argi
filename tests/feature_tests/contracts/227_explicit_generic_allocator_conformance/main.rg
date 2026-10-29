ConstructionArgs := #(.Provider: Type) (.allocator: $&Provider, .length: UIntNative)

Construct#(.Target: Type, .Args: Type): Contract = (
    .Result    : Type
    .construct : (.args: Args, .error_tracer: $&Virtual#(ErrorTracer)) -> (.result: Result)
)

Owner := (.allocation: Allocation)

implement#(.A: Type: Allocator) Construct#(Owner, ConstructionArgs#(A)) (
    .Result    : Type = Errable#(Owner, (..out_of_memory))
    .construct = (.args: ConstructionArgs#(A), .error_tracer: $&Virtual#(ErrorTracer)) -> (
        .result : Result
    ) {
        assume error_tracer

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
    assume error_tracer ::= $&noop_error_tracer
    args :: ConstructionArgs#(PageAllocator) = (
        .allocator = system.page_allocator
        .length    = 4
    )
    owner ::= unwrap_or_abort(
        Construct#(Owner, ConstructionArgs#(PageAllocator)).construct(.args = args)
    )
}
