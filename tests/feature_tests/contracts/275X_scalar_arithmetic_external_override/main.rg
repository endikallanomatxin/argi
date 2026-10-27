implement Add#(Int32, Int32) (
    .Result : Type = Int64
    .add    = (.left: Int32, .right: Int32) -> (.result: Result) {
        result = left | convert#(.to: Int64)(_)
    }
)

choose := #(.T: Type) (.left: T, .right: T) -> (.result: Add#(T, T).Result) {
    result = ~[left + right]
}

main := () -> (.status_code: Int32 = 0) {
    direct ::= 7 + 9
    generic ::= choose(7, 9)
    if direct != 7 or generic != 7 { status_code = 1 }
}
