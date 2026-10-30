CliArgumentViews := (._values: ArrayView#(.t: StringView))

CliArgumentViewsInitArgs: Type = (.values: ArrayView#(.t: StringView))

implement Init#(CliArgumentViews, CliArgumentViewsInitArgs) (
    .Result : Type = CliArgumentViews

    .init = CliArgumentViewsInitArgs -> (.result: Result) {
        _init_values ::= values

        result = (._values = _init_values)
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
