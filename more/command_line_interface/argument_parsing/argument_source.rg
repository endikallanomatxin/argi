ArgumentSource#(.Source: Type): Contract = (
    .length : (.self: &Source) -> (.count: UIntNative) where {}
    .get    : (.self: &Source, .index: UIntNative) -> (
        .result : Errable#(StringView, (..out_of_bounds, ..invalid_utf8))
    ) where {
        on result ..ok { depends_on(result, self) }
        on result ..error {}

    }
)

ArgumentViews := (._values: ArrayView#(.t: StringView))

ArgumentViewsInitArgs: Type = (.values: ArrayView#(.t: StringView))

implement Init#(ArgumentViews, ArgumentViewsInitArgs) (
    .Result : Type = ArgumentViews

    .init = ArgumentViewsInitArgs -> (.result: Result) {
        _init_values ::= values

        result = (._values = _init_values)
    }
)

implement ArgumentSource#(ArgumentViews) (
    .length = (.self: &ArgumentViews) -> (.count: UIntNative) {
        count = length(&self&._values).count
    }

    .get = (.self: &ArgumentViews, .index: UIntNative) -> (
        .result : Errable#(StringView, (..out_of_bounds, ..invalid_utf8))
    ) {

        value ::= get(&self&._values, .index = index)!
        result = ..ok value
    }
)

implement ArgumentSource#(Arguments) (
    .length = (.self: &Arguments) -> (.count: UIntNative) {
        count = self&.count
    }

    .get = (.self: &Arguments, .index: UIntNative) -> (
        .result : Errable#(StringView, (..out_of_bounds, ..invalid_utf8))
    ) {

        if index >= self&.count {
            result = ..error(.reason = ..out_of_bounds)
            return
        }

        result = argument_view_at(self, .index = index)
    }
)
