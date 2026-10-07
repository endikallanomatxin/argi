..failed

Source: Abstract = (
    get(.self: &Self) -> (.result: Errable#(Int32, (..failed))) where {
        on ..missing {}
        on ..error { depends_on(result, error_tracer) }
    }
)

Cell: Type = (.value: Int32)

Cell implements Source

get(.self: &Cell) -> (.result: Errable#(Int32, (..failed))) := {
    if self&.value == 0 { result = ..error(.reason = ..failed) } else { result = ..ok self&.value }
}

read_source(.source: &Virtual#(Source)) -> (.result: Errable#(Int32, (..failed))) := {
    result = get(source)
}

main() -> (.status_code: Int32 = 0) := {
    cell ::= Cell(42)
    source ::= to_virtual#(Source)(&cell)
    match read_source(&source) {
        ..ok value { if value != 42 { status_code = 1 } }
        ..error _ { status_code = 1 }
    }
}
