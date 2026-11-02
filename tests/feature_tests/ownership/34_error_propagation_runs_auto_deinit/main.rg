Resource: Type = ()

..test_error
..cleanup_error

dummy_counter :: Int32 = 0

ResourceInitArgs: Type = ()

implement Init#(Resource, ResourceInitArgs) (
    .Result : Type = Resource

    .init = ResourceInitArgs -> (.result: Result) {
        result = ()
    }
)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        dummy_counter = dummy_counter + 1
    }
)

fail := (.error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(.t: Int32, .reasons: (..test_error))
) {
    assume error_tracer

    result = ..error(.reason = ..test_error)
}

propagate := (.error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(.t: Int32, .reasons: (..test_error, ..cleanup_error))
) {
    assume error_tracer

    handle := Resource()
    value := fail()!
    if dummy_counter != 1 {
        result = ..error(.reason = ..cleanup_error)
        return
    }
    result = ..ok value
}

main := () -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    dummy_counter = 0
    result := propagate()

    if is(.value = result, .variant = ..error) {
        if dummy_counter != 1 {
            status_code = 1
            return
        }
        status_code = 0
    } else {
        status_code = 2
    }
}
