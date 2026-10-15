CliArgumentViews: Type = (._values: ArrayViewRO#(.t: StringView))

implement Init#(CliArgumentViews, (.values: ArrayViewRO#(.t: StringView))) (
    .Result : Type = CliArgumentViews
    .init   = (.args: (.values: ArrayViewRO#(.t: StringView))) -> (.result: Result) {
        values ::= args.values

        result = (._values = values)
    }
)

implement ArgumentSource#(CliArgumentViews) (
    .length = (.self: &CliArgumentViews) -> (.count: UIntNative) {
        count = length(&self&._values).count
    }

    .get = (.self: &CliArgumentViews, .index: UIntNative) -> (
        .result : Errable#(StringView, (..out_of_bounds, ..invalid_utf8))
    ) {
        value ::= get(&self&._values, .index = index)!
        result = ..ok value
    }
)
