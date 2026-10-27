dep := import ("./dep")

Buffer := #(.n: Int) (.values: Array#(.n = n, .t: Int32))

main := () -> () {
    buffer ::= Buffer#(.n = dep.Shape#(dep.Cell).Count)((42, 0))
    if dep.first#(.n = dep.Shape#(dep.Cell).Count)(&buffer.values).value != 42 { abort }
}
