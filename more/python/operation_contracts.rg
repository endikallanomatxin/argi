_PythonInteger#(.Value: Type): Contract = (
    .make_integer : (
        .self         : &Python,
        .value        : Value,
        .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
    ) -> (.result: Errable#(Object, (..python_error)))
)

implement _PythonInteger#(Int64) (.make_integer = _python_signed_integer)

implement _PythonInteger#(UInt64) (.make_integer = _python_unsigned_integer)

integer := #(.Value: Type: _PythonInteger#(Value)) (
    .self         : &Python,
    .value        : Value,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(Object, (..python_error))) {
    assume error_tracer

    result = ~_PythonInteger#(Value).make_integer(.self = self, .value = value)
}

_PythonClone#(.Value: Type): Contract = (
    .Result    : Type
    .duplicate : (.self: &Value) -> (.result: Result)
)

implement _PythonClone#(Object) (
    .Result    : Type = Errable#(Object, (..python_error))
    .duplicate = _python_object_clone
)

implement _PythonClone#(Exception) (
    .Result    : Type = Exception
    .duplicate = _python_exception_clone
)

clone := #(.Value: Type: _PythonClone#(Value)) (
    .self         : &Value,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: _PythonClone#(Value).Result) {
    assume error_tracer
    result = ~_PythonClone#(Value).duplicate(.self = self)
}

_PythonKeywords#(.Values: Type): Contract = (
    .make_keywords : (
        .self         : &Python,
        .values       : Values,
        .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
    ) -> (.result: Errable#(Object, (..python_error)))
)

keyword_arguments := #(.Values: Type: _PythonKeywords#(Values)) (
    .self         : &Python,
    .values       : Values,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(Object, (..python_error))) {
    assume error_tracer

    result = ~_PythonKeywords#(Values).make_keywords(.self = self, .values = values)
}

_PythonCall#(.Arguments: Type): Contract = (
    .invoke : (
        .self         : &Object,
        .arguments    : Arguments,
        .keywords     : ?&Object,
        .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
    ) -> (.result: Errable#(Object, (..python_error)))
)

call := #(.Arguments: Type: _PythonCall#(Arguments)) (
    .self         : &Object,
    .arguments    : Arguments = _no_arguments(),
    .keywords     : ?&Object  = _no_keywords(),
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(Object, (..python_error))) {
    assume error_tracer

    result = ~_PythonCall#(
        Arguments
    ).invoke(.self = self, .arguments = arguments, .keywords = keywords)
}

call_method := #(.Arguments: Type: _PythonCall#(Arguments)) (
    .self         : &Object,
    .name         : StringView,
    .arguments    : Arguments   = _no_arguments(),
    .keywords     : ?&Object    = _no_keywords(),
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(Object, (..python_error))) {
    assume error_tracer

    method ::= attribute(.self = self, .name = name)!
    result = ~call(.self = &method, .arguments = arguments, .keywords = keywords)
}
