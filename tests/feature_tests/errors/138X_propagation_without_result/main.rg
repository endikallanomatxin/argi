fail := () -> (.result: Errable#(Int32, (..expected))) {
    result = ..error(.reason = ..expected)
}
main := () -> () { value ::= fail()! }
