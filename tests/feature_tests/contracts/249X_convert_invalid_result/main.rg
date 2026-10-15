Source: Type = (.value: Int32)
Target: Type = (.value: Int32)
implement Convert#(Source, Target) (
    .Result: Type = Int32
    .convert = (.value: Source) -> (.result: Result) { result = value.value }
)
main := () -> () {}
