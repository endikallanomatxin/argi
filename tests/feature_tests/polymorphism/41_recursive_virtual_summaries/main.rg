View#(.Participant: Type): Contract = (
    .get : (.self: &Participant, .depth: Int32) -> (.value: &Int32) where depends_on(value, self)
)

Cell := (.value: Int32)

Other := (.value: Int32)

implement View#(Cell) (.get = _impl_get_Cell)

implement View#(Other) (.get = _impl_get_Other)

identity := (.value: &Int32, .depth: Int32) -> (.result: &Int32) {
    if depth == 0 {
        result = value
    } else {
        result = identity(.value = value, .depth = depth - 1)
    }
}

first := (.value: &Int32, .depth: Int32) -> (.result: &Int32) {
    if depth == 0 {
        result = value
    } else {
        result = second(.value = value, .depth = depth - 1)
    }
}

second := (.value: &Int32, .depth: Int32) -> (.result: &Int32) {
    result = first(.value = value, .depth = depth)
}

read := (.view: &Virtual#(.contract: View), .depth: Int32) -> (.value: &Int32) {
    value = get(.self = view, .depth = depth)
}

_impl_get_Cell := (.self: &Cell, .depth: Int32) -> (.value: &Int32) {
    if depth == 0 {
        value = &self&.value
    } else {
        view ::= to_virtual#(View)(self)
        value = read(.view = &view, .depth = depth - 1)
    }
}

_impl_get_Other := (.self: &Other, .depth: Int32) -> (.value: &Int32) {
    value = first(.value = &self&.value, .depth = depth)
}

main := () -> (.status_code: Int32 = 0) {
    cell :: Cell = (.value = 42)
    other :: Other = (.value = 17)
    view ::= to_virtual#(View)(&cell)
    other_view ::= to_virtual#(View)(&other)
    a ::= identity(.value = &cell.value, .depth = 3)
    b ::= second(.value = &other.value, .depth = 3)
    c ::= read(.view = &view, .depth = 3)
    d ::= read(.view = &other_view, .depth = 3)
    if a&!= 42 or b&!= 17 or c&!= 42 or d&!= 17 { status_code = 1 }
}
