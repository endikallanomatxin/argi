CliArgumentViews: Type = (._values: ArrayViewRO#(.t: StringView))

CliArgumentViews init(.values: ArrayViewRO#(.t: StringView)) -> (.result: CliArgumentViews) := {
    result = (._values = values)
}

implement ArgumentSource#(CliArgumentViews) (
    .length = (.self: &CliArgumentViews) -> (.count: UIntNative) {
        count = length(&self&._values).count
    }

    .get = (
            .self  : &CliArgumentViews,
            .index : UIntNative
        ) -> (
            .result : Errable#(StringView, (..out_of_bounds))
        ) {
        result = get(&self&._values, .index = index)
    }
)
