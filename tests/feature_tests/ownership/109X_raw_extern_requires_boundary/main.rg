call_raw() -> () := {
    pointer ::= malloc(.size = 1)
}

main() -> (.status_code: Int32) := {
    call_raw()
    status_code = 0
}
