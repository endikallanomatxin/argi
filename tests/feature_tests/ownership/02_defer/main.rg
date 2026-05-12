-- Ensure #defer executes at scope exit.
set_zero(.target: $&Int32) -> () := {
    target& = 0
}

main () -> (.status_code: Int32) := {
    status_code = 1
    #defer set_zero(.target=$&status_code)
    status_code = 2
}
