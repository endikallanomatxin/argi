Shape#(.Input: Type): Contract = (
    .Count : Int
)

Cell: Type = ()

implement Shape#(Cell) (.Count: Int = 2)

Buffer := #(.n: Int) (.values: Array#(.n = n, .t: Int32))

sum := (.values: &Array#(.n = Shape#(Cell).Count, .t: Int32)) -> (.value: Int32) {
    value = [values&[0] + values&[1]]
}

read_buffer := (
    .buffer: &Buffer#(.n = Shape#(Cell).Count), .error_tracer: $&Virtual#(ErrorTracer)
) -> (.value: Int32) {
    assume error_tracer
    value = sum(&buffer&.values).value
}

main := () -> () {
    assume error_tracer ::= $&noop_error_tracer
    buffer ::= Buffer#(.n = Shape#(Cell).Count)((20, 22))
    if read_buffer(&buffer).value != 42 { abort }
}
