Source := (.value: Int32)

Target := (.value: Int32)

implement Convert#(Source, Target) (
    .Result  : Type = Errable#(Int32, (..failure))
    .convert = (.value: Source, .error_tracer: $&Virtual#(ErrorTracer)) -> (.result: Result) {
        assume error_tracer
        result = ..ok value.value
    }
)

main := () -> () {}
