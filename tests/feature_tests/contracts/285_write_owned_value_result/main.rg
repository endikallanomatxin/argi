drops :: Int32 = 0
Owner: Type = (.value: Int32)
Sink: Type = ()
implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () { drops = drops + 1 }
)
implement WriteValue#(Sink, Owner) (
    .Result: Type = Owner
    .write_value = (.self: $&Sink, .value: Owner) -> (.result: Owner) {
        result = ~value
    }
)
exercise := () -> () {
    sink ::= Sink()
    owner ::= Owner(42)
    returned ::= ~write(.self = $&sink, .value = ~owner)
    if returned.value != 42 { abort }
}
main := () -> (.status_code: Int32 = 0) {
    exercise()
    if drops != 1 { status_code = 1 }
}
