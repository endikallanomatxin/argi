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

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume allocator := system.page_allocator
    first ::= unwrap_or_abort(Owner(.allocator = allocator, .length = 8))
    second ::= unwrap_or_abort(Owner())
    storage ::= GeneralPurposeAllocator(.allocator = allocator)
    third ::= unwrap_or_abort(Owner(.allocator = $&storage, .length = 16))
}
