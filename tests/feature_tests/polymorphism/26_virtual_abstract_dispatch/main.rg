Shape : Abstract = (
    get_value(.self: &Self) -> (.value: Int32)
    set_value(.self: $&Self, .value: Int32) -> ()
)

Box : Type = (.value: Int32)
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
    set_value(.self = $&erased, .value = 43)
    dynamic_value ::= get_value(.self = &erased)
    if dynamic_value == 43 and box.value == 43 {
        status_code = 0
    } else {
        status_code = 1
    }
}
