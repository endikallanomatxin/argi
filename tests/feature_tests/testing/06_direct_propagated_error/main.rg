..file_not_found

some_fallible_call() -> (.result: Errable#(.t: Void, .reasons: (..file_not_found))) := {
    result = ..error(.reason = ..file_not_found)
}

test direct_propagation(.system: System = System()) -> !() := {
    some_fallible_call()!
}
