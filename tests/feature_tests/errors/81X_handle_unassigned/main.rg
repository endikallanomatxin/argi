..missing

fail() -> (.result: Errable#(.t: Int32, .reasons: (..missing))) := {
    result = ..error(.reason = ..missing)
}

main() -> (.status_code: Int32 = 0) := {
    number ::= fail() handle error, value {}
    status_code = number
}
