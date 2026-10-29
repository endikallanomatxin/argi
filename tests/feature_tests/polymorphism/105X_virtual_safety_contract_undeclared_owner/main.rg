Factory#(.Participant: Type): Contract = (
    .make : (
        .self         : &Participant,
        .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
    ) -> (.value: Errable#(Allocation, (..out_of_memory)))
    where depends_on(value, self, error_tracer)
)

Cell := (.allocator: $&Virtual#(Allocator))

implement Factory#(Cell) (.make = _impl_make_Cell)

_impl_make_Cell := (
    .self         : &Cell,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.value: Errable#(Allocation, (..out_of_memory))) {
    assume error_tracer

    value = allocate_bytes(self&.allocator, .size = 1, .alignment = 1)
}

main := (.system: System) -> () {
    backing ::= to_virtual#(Allocator)(system.page_allocator)
    cell ::= Cell($&backing)
    factory ::= to_virtual#(Factory)(&cell)
}
