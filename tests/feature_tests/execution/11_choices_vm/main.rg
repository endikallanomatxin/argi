Result: Type = (..ok(.value: Int32), ..empty)

make := (.value: Int32) -> (.result: Result) { result = ..ok(.value = value) }

read := (.result: Result) -> (.value: Int32) {
    match result {
        ..ok payload { value = payload.value }
        ..empty { value = 0 }
    }
}

select := (.value: $&Result, .calls: $&Int32) -> (.result: $&Result) {
    calls&= calls&+ 1
    result = value
}

ReferenceResult: Type = (..some(.value: $&Int32), ..empty)

wrap_reference := (.value: $&Int32) -> (.result: ReferenceResult) {
    result = ..some(.value = value)
}

unwrap_reference := (.value: ReferenceResult) -> (.result: $&Int32) {
    match value {
        ..some payload { result = payload.value }
        ..empty { abort }
    }
}

exercise := () -> (.answer: Int32 = 0) {
    result :: Result = make(.value = 1)
    saved ::= result
    match result {
        ..ok $&payload { payload&.value = 42 }
        ..empty { abort }
    }
    calls :: Int32 = 0
    match select(.value = $&result, .calls = $&calls)&{
        ..ok&payload { if payload&.value != 42 { abort } }
        ..empty { abort }
    }
    if calls != 1 { abort }
    number :: Int32 = 41
    wrapped := wrap_reference(.value = $&number)
    reference := unwrap_reference(.value = wrapped)
    reference&= reference&+ 1
    if number != 42 { abort }
    if read(.result = saved) != 1 { abort }
    if result != ..ok { abort }
    answer = read(.result = result)
    result = ..empty
    if read(.result = result) != 0 { abort }
}

main := () -> (.status_code: Int32 = 0) {
    compiled ::= #run () -> (.value: Int32) { value = exercise() }
    if compiled != 42 { abort }
    status_code = exercise()
}
