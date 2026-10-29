Owner := (.allocation: Allocation)

OwnerInitArgs: Type = #(.A: Type: Allocator) (
    .allocator : $&A,
    .length    : UIntNative = 4
    ,
    .error_tracer : $&Virtual#(ErrorTracer)
)

implement#(.A: Type: Allocator) Init#(Owner, OwnerInitArgs#(A)) (
    .Result : Type = Errable#(Owner, (..out_of_memory))

    .init = OwnerInitArgs#(A) -> (.result: Result) {
        assume error_tracer

        allocation ::= Allocator#(A).allocate(.self = allocator, .size = length, .alignment = 1)!
        result = ..ok(.allocation = ~allocation)
    }
)

implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () { deinit(.self = $&self&.allocation) }
)

escape := (.allocator: $&PageAllocator, .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Owner
) {
    assume error_tracer
    storage ::= GeneralPurposeAllocator(.allocator = allocator)
    result = ~unwrap_or_abort(Owner(.allocator = $&storage))
}

main := (.system: System) -> () {
    assume error_tracer ::= $&noop_error_tracer
    owner ::= escape(system.page_allocator)
}
