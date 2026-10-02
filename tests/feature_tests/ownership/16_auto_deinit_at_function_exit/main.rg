Resource : Type = ()

dummy_counter :: Int32 = 0
global_counter_ptr :: $&Int32 = $&dummy_counter

init(.p: $&Resource, .counter: $&Int32) -> () := {
    global_counter_ptr = counter
}

deinit(.res: $&Resource) -> () := {
    global_counter_ptr& = global_counter_ptr& + 1
}

create_and_drop(.counter: $&Int32) -> () := {
    handle := Resource(.counter = counter)
}

main() -> (.status_code: Int32) := {
    counter :: Int32 = 0
    create_and_drop(.counter = $&counter)
    status_code = 0
    if counter != 1 {
        status_code = 7
    }
}
