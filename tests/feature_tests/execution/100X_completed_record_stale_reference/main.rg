Pair: Type = (.first: Int32, .second: Int32)

implement Deinit#(Pair) (
    .deinit = (.self: $&Pair) -> () {}
)

main := () -> (.status_code: Int32) {
    pair :: Pair = (.first = 40, .second = 2)
    old ::= &pair
    deinit(.self = $&pair)
    pair.first = 40
    pair.second = 2
    complete ::= ~pair
    status_code = old&.first + complete.second
}
