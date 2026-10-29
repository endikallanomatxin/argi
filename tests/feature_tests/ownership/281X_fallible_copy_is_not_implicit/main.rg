FallibleValue := (
    .value : Int32
)

implement#(.Provider: Type: Allocator) FalliblyCopyable#(FallibleValue, Provider) (
    .reasons : Type = (..copy_failed)
    .copy    = (
        .self         : &FallibleValue,
        .allocator    : $&Provider,
        .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
    ) -> (.result: Errable#(.t: FallibleValue, .reasons: (..copy_failed))) {
        assume error_tracer

        assume allocator

        result = ..ok(.value = self&.value)
    }

)

main := () -> (.status_code: Int32) {
    first :: FallibleValue = (.value = 42)
    second ::= first
    status_code = second.value - 42
}
