..failed

Source: Abstract = (
    domain storage
    get(.self: &Self) -> (.value: &Int32) where depends_on(value, self.storage)
    edit(.self: $&Self, .succeed: Bool) -> (.result: Errable#(?Int32, (..failed))) where {
        on result ..ok {
            on result ..some { invalidates(self.storage) }
            on result ..none {}
        }
        on result ..error { depends_on(result, error_tracer) }
    }
)

Cell: Type = (.value: Int32, .other: Int32)

Cell implements Source where { storage(self.value) }

get(.self: &Cell) -> (.value: &Int32) := { value = &self&.value }

edit(.self: $&Cell, .succeed: Bool) -> (.result: Errable#(?Int32, (..failed))) := {
    if succeed {
        self&.value = 42
        result = ..ok ..some(.value = 42)
        return
    }

    result = ..ok ..none
}

apply_edit(.source: $&Virtual#(Source), .succeed: Bool) -> (.result: Errable#(?Int32, (..failed))) := {
    result = edit(source, succeed)
}

main() -> (.status_code: Int32 = 0) := {
    cell ::= Cell(41, 9)
    source ::= to_virtual#(Source)($&cell)
    previous ::= get(&source)
    other ::= &cell.other
    result ::= apply_edit($&source, false)

    match result {
        ..ok ~optional {
            match optional {
                ..none { if previous&!= 41 { status_code = 1 } }
                ..some _ { status_code = 2 }
            }
        }
        ..error _ { status_code = 4 }
    }
    if other&!= 9 { status_code = 3 }
}
