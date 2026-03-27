choose2 (.a: &Any, .b: &Int32) -> (.r: Int32) := {
    r = 10
}

choose2 (.a: &Int32, .b: &Any) -> (.r: Int32) := {
    r = 20
}

main () -> (.status_code: Int32) := {
    i: Int32 = 5
    -- ambiguous: two best matches
    status_code = choose2(.a = &i, .b = &i).r
}
