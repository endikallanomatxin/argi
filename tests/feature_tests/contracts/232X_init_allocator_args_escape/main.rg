Owner := (.allocation: Allocation)

OwnerInitArgs: Type = #(.A: Type: Allocator) (
    .allocator : $&A,
    .length    : UIntNative = 4
    ,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
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

escape := (.allocator: $&PageAllocator) -> (.result: Owner) {
    storage ::= GeneralPurposeAllocator(.allocator = allocator)
    result = ~unwrap_or_abort(Owner(.allocator = $&storage))
}

main := (.system: System) -> () { owner ::= escape(system.page_allocator) }
