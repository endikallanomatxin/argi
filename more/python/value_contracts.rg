PythonValue#(.Value: Type): Contract = (
    .convert_value : (
        .self         : &Python,
        .value        : Value,
        .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
    ) -> (.result: Errable#(Object, (..python_error)))
)

to_object := #(.Value: Type: PythonValue#(Value)) (
    .self         : &Python,
    .value        : Value,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(Object, (..python_error))) {
    assume error_tracer

    result = ~PythonValue#(Value).convert_value(.self = self, .value = ~value)
}
