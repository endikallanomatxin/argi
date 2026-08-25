Shape : Abstract = (
    get_value(.self: &Self) -> (.value: Int32)
    set_value(.self: $&Self, .value: Int32) -> ()
)

Box : Type = (
    .value: Int32
)

Box implements Shape

get_value(.self: &Box) -> (.value: Int32) := {
    value = self&.value
}

set_value(.self: $&Box, .value: Int32) -> () := {
    self&.value = value
}

main() -> (.status_code: Int32) := {
    box :: Box = (.value = 42)
    erased :: Virtual#(.abstract: Shape) = to_virtual#(.abstract: Shape)(.value = $&box)
    original ::= cast#(.to: UIntNative)(.value = $&box)
    erased_data ::= cast#(.to: UIntNative)(.value = erased.data)
    dynamic_value ::= get_value(.self = &erased)
    representation_ok ::= original == erased_data
    set_value(.self = $&erased, .value = 43)
    if representation_ok and dynamic_value == 42 and box.value == 43 {
        status_code = 0
    } else {
        status_code = 1
    }
}
