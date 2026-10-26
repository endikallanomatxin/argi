-- Multiple generic parameters (struct types)

Pair2 := <.a: Type, .b: Type> (
    .x : a,
    .y : b
)

main := () -> (.status_code: Int32) {
    p: Pair2<.a: Int32, .b: UnicodeScalar> = (.x = 20, .y = 'X')
    status_code = p.x
}
