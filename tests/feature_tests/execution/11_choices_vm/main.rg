Result: Type = (..ok(.value: Int32), ..empty)

make(.value: Int32) -> (.result: Result) := { result = ..ok(.value = value) }

read(.result: Result) -> (.value: Int32) := {
    match result {
        ..ok payload { value = payload.value }
        ..empty { value = 0 }
    }
}

main() -> (.status_code: Int32 = 0) := {
    result :: Result = make(.value = 1)
    saved ::= result
    match result {
        ..ok $&payload { payload&.value = 42 }
        ..empty { abort }
    }
    if read(.result = saved) != 1 { abort }
    if result != ..ok { abort }
    status_code = read(.result = result)
    result = ..empty
    if read(.result = result) != 0 { abort }
}
