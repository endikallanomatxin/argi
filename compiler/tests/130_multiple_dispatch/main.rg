choose (.p: &Any) -> (.r: Int32) := {
    r = 1
}

choose (.p: &Int32) -> (.r: Int32) := {
    r = 2
}

main () -> (.status_code: Int32) := {
    i: Int32 = 0
    status_code = choose(.p = &i).r
}
