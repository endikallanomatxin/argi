Source: Abstract = (
    domain storage
    get(.self: &Self) -> (.value: &Int32) where depends_on(value, self.storage)
    edit(.self: $&Self, .succeed: Bool) -> (.result: ?Int32) where {
        on result ..some { invalidates(self.storage) }
        on result ..none {}
    }
)

Cell: Type = (.value: Int32, .other: Int32)

Cell implements Source where { storage(self.value) }

get(.self: &Cell) -> (.value: &Int32) := { value = &self&.value }

edit(.self: $&Cell, .succeed: Bool) -> (.result: ?Int32) := {
    if succeed {
        self&.value = 42
        result = ..some(.value = 42)
        return
    }

    result = ..none
}

apply_edit(.source: $&Virtual#(Source), .succeed: Bool) -> (.result: ?Int32) := {
    result = edit(source, succeed)
}

main() -> (.status_code: Int32 = 0) := {
    cell ::= Cell(41, 9)
    source ::= to_virtual#(Source)($&cell)
    previous ::= get(&source)
    other ::= &cell.other
    result ::= apply_edit($&source, false)

    match result {
        ..none { if previous&!= 41 { status_code = 1 } }
        ..some _ { status_code = 2 }
    }
    if other&!= 9 { status_code = 3 }
}
