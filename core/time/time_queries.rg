TimeCompare#(.Value: Type): Contract = (
    .compare_value : (.left: Value, .right: Value) -> (.order: Int32)
)

compare#(.Value: Type: TimeCompare#(Value)) := (.left: Value, .right: Value) -> (.order: Int32) {
    order = TimeCompare#(Value).compare_value(.left = left, .right = right)
}

NanosecondCount#(.Value: Type): Contract = (
    .Count            : Type
    .nanosecond_count : (.self: &Value) -> (.value: Count)
)

nanoseconds#(
        .Value : Type: NanosecondCount#(Value)
    ) := (
        .self : &Value
    ) -> (
        .value : NanosecondCount#(Value).Count
    ) {
    value = NanosecondCount#(Value).nanosecond_count(.self = self)
}
