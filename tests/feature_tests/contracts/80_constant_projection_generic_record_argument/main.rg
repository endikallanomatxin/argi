Shape#(.Input: Type): Contract = (
    .Count : Int
)

Cell: Type = ()

implement Shape#(Cell) (.Count: Int = 2)

Buffer := #(.n: Int) (.values: Array#(.n = n, .t: Int32))

Box := #(.T: Type) (.buffer: Buffer#(.n = Shape#(T).Count))

sum := #(.T: Type) (.tag: T, .values: &Array#(.n = Shape#(T).Count, .t: Int32)) -> (
    .value : Int32
) {
    value = [values&[0] + values&[1]]
}

main := () -> () {
    assume error_tracer ::= $&noop_error_tracer
    box ::= Box#(Cell)(Buffer#(.n = 2)((20, 22)))
    if sum(Cell(), &box.buffer.values).value != 42 { abort }
}
