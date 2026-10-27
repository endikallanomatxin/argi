api := import ("./api")

Local := (.value: Int32)

implement#(.T: Type) api.Related#(Local, T) (
    .value = (.left: &Local, .right: &T) -> (.result: Int32) { result = left&.value }
)

main := () -> (.status_code: Int32 = 0) {
    local ::= Local(42)
    right :: UInt8 = 1
    if api.Related#(Local, UInt8).value(&local, &right) != 42 { abort }
}
