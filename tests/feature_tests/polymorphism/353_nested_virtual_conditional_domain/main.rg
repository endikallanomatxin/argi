Source#(.Participant: Type): Contract = (
    .storage: Region#(Participant)
    .get  : (.self: &Participant) -> (.value: &Int32) where depends_on(value, self.storage)
    .edit : (.self: $&Participant, .succeed: Bool) -> (.result: ?Int32) where {
        on result ..some { invalidates(self.storage) }
        on result ..none {}
    }
)

Cell := (.value: Int32, .other: Int32)

implement Source#(Cell) (
    .storage = region(self.value),
    .get = _impl_get_Cell, .edit = _impl_edit_Cell)

_impl_get_Cell := (.self: &Cell) -> (.value: &Int32) { value = &self&.value }

_impl_edit_Cell := (.self: $&Cell, .succeed: Bool) -> (.result: ?Int32) {
    if succeed {
        self&.value = 42
        result = ..some(.value = 42)
        return
    }

    result = ..none
}

Holder := (.source: Virtual#(Source))
check := (.holder: $&Holder, .succeed: Bool) -> () {
    previous ::= get(&holder&.source)
    result ::= edit($&holder&.source, succeed)
    match result {
        ..none { if previous& != 41 { abort } }
        ..some _ { current ::= get(&holder&.source)
            if current& != 42 { abort } }
    }
}
main := () -> () {
    cell ::= Cell(41, 9)
    holder ::= Holder(Virtual#(Source)($&cell))
    check($&holder, false)
}
