Convert#(.Source: Type, .Target: Type): Contract = (
    .Result  : Type
    .convert : (.value: Source) -> (.result: Result)
)

-- The source comes from the value; the destination is explicit. Associated
-- results are determined by that tuple, never used to infer its participants.
convert := #(.Source: Type, .to: Type) (
    .value        : Source,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Convert#(Source, to).Result) {
    assume error_tracer
    result = ~Convert#(Source, to).convert(.value = ~value)
}
