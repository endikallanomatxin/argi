..failed

Source: Abstract = (
    get(.self: &Self) -> (.result: Errable#(Int32, (..failed))) where {
        on result ..ok {
            on result ..some { depends_on(result, self) }
            on result ..none {}
        }
        on result ..error { depends_on(result, error_tracer) }
    }
)

Cell: Type = (.value: Int32)

Cell implements Source

get(.self: &Cell) -> (.result: Errable#(Int32, (..failed))) := {
    result = ..ok 42
}

read_source(.source: &Virtual#(Source)) -> (.result: Errable#(Int32, (..failed))) := {
    result = get(source)
}

main() -> (.status_code: Int32 = 0) := {
    cell ::= Cell(42)
    source ::= to_virtual#(Source)(&cell)

    match read_source(&source) {
        ..ok ~optional {
            match optional {
                ..some reference { if reference.value&!= 42 { status_code = 1 } }
                ..none { status_code = 2 }
            }
        }
        ..error _ { status_code = 3 }
    }
}
