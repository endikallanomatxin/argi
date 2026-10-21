Choice: Type = (..empty, ..some(.value: Int32))

Record: Type = (.choice: Choice, .later: Int32)

exercise := () -> (.result: Int32) {
    record :: Record
    record.choice = ..some(.value = 41)
    saved ::= record.choice
    match record.choice {
        ..empty { abort }
        ..some $&payload { payload&.value = 42 }
    }
    match saved {
        ..empty { abort }
        ..some payload { if payload.value != 41 { abort } }
    }
    record.later = 7
    match record.choice {
        ..empty { abort }
        ..some payload { result = payload.value }
    }
    record.choice = ..empty
    if record.choice != ..empty { abort }
}

main := () -> (.status_code: Int32) {
    if [#run () -> (.value: Int32) { value = exercise() }] != 42 { abort }
    #if exercise() == 42 { status_code = exercise() } #else { abort }
}
