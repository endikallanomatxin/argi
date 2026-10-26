implement Add<Int32, Int32, (.left: Int32, .right: Int32)> (
    .Result : Type = Int64
    .add    = (.args: (.left: Int32, .right: Int32)) -> (.result: Result) {
        result = args.left | convert<.to: Int64>(_)
    }
)

choose := <.T: Type> (.left: T, .right: T) -> (.result: Add<T, T, (.left: T, .right: T)>.Result) {
    result = ~[left + right]
}

main := () -> (.status_code: Int32 = 0) {
    direct ::= 7 + 9
    generic ::= choose(7, 9)
    if direct != 7 or generic != 7 { status_code = 1 }
}
