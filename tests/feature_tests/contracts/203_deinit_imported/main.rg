helper ::= import("./helper")
create := (.counter: $&Int32) -> () { value ::= helper.Owner(.value = 42, .counter = counter) }
main := () -> (.status_code: Int32 = 0) {
    count :: Int32 = 0
    create(.counter = $&count)
    if count != 1 { abort }
}
