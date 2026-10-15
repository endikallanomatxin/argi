..failed

Source#(.Participant: Type): Contract = (
    .get: (.self: &Participant) -> (.result: Errable#(Int32, (..failed))) where {
        on result ..missing {}
        on result ..error { depends_on(result, error_tracer) }
    }
)

Cell: Type = (.value: Int32)

implement Source#(Cell) (.get = _impl_get_Cell)

_impl_get_Cell := (.self: &Cell) -> (.result: Errable#(Int32, (..failed)))  {
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
