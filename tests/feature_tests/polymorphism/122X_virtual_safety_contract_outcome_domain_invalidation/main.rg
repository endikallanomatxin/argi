Source#(.Participant: Type): Contract = (
    domain storage
    .get  : (.self: &Participant) -> (.value: &Int32) where depends_on(value, self.storage)
    .edit : (.self: $&Participant, .succeed: Bool) -> (.result: ?Int32) where {
        on result ..some { invalidates(self.storage) }
        on result ..none {}
    }
)

Cell := (.value: Int32, .other: Int32)

implement Source#(Cell) (.get = _impl_get_Cell, .edit = _impl_edit_Cell) where {
    storage(self.value)
}

_impl_get_Cell := (.self: &Cell) -> (.value: &Int32) { value = &self&.value }

_impl_edit_Cell := (.self: $&Cell, .succeed: Bool) -> (.result: ?Int32) {
    if succeed {
        self&.value = 42
        result = ..some(.value = 42)
        return
    }

    result = ..none
}

apply_edit := (.source: $&Virtual#(Source), .succeed: Bool) -> (.result: ?Int32) {
    result = edit(source, succeed)
}

main := () -> (.status_code: Int32 = 0) {

    cell ::= Cell(41, 9)
    source ::= to_virtual#(Source)($&cell)
    previous ::= get(&source)
    other ::= &cell.other
    result ::= apply_edit($&source, true)

    match result {
        ..none { if previous&!= 41 { status_code = 1 } }
        ..some _ { if previous&!= 42 { status_code = 2 } }
    }
    if other&!= 9 { status_code = 3 }
}
