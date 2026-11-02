Source := (.value: Int32)

Target := (.value: Int32)

implement Convert#(Source, Target) (
    .Result  : Type = Errable#(Int32, (..failure))
    .convert = (.value: Source) -> (.result: Result) {

        result = ..ok value.value
    }
)

main := () -> () {}
