Shape#(.Participant: Type): Contract = (
    .get_value: (.self: &Participant) -> (.value: Int32) where {}
    .set_value: (.self: $&Participant, .value: Int32) -> () where {}
)

Box: Type = (.value: Int32)

implement Shape#(Box) (.get_value = _impl_get_value_Box, .set_value = _impl_set_value_Box)

_impl_get_value_Box := (.self: &Box) -> (.value: Int32)  {
    value = self&.value
}

_impl_set_value_Box := (.self: $&Box, .value: Int32) -> ()  {
    self&.value = value
}

main() -> (.status_code: Int32) := {
    box :: Box = (.value = 42)
    erased :: Virtual#(.abstract: Shape) = to_virtual#(.abstract: Shape)(.value = $&box)
    set_value(.self = $&erased, .value = 43)
    dynamic_value ::= get_value(.self = &erased)
    if dynamic_value == 43 and box.value == 43 {
        status_code = 0
    } else {
        status_code = 1
    }
}
