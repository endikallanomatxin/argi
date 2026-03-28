Resource : Type = ()

dummy_counter :: Int32 = 0
global_counter_ptr :: $&Int32 = $&dummy_counter

init(.p: $&Resource, .counter: $&Int32) -> () := {
    global_counter_ptr = counter
}

deinit(.res: $&Resource) -> () := {
    global_counter_ptr& = global_counter_ptr& + 1
}

verify(.counter: $&Int32, .status: $&Int32) -> () := {
    if counter& != 0 {
        status& = 7
    }
}

main() -> (.status_code: Int32) := {
    counter :: Int32 = 0
    status_code = 0
    #defer verify(.counter = $&counter, .status = $&status_code)
    handle := Resource(.counter = $&counter)
    #keep handle
}
