Resource : Type = ()

dummy_counter :: Int32 = 0
dummy_status :: Int32 = 0

global_counter_ptr :: $&Int32 = $&dummy_counter
global_status_ptr :: $&Int32 = $&dummy_status

init(.res: $&Resource, .counter: $&Int32, .status: $&Int32) -> () := {
    puts(.string="Initializing resource\n")
    global_counter_ptr = counter
    global_status_ptr = status
}

deinit(.res: $&Resource) -> () := {
    puts(.string="Deinitializing resource\n")
    global_counter_ptr& = global_counter_ptr& + 1
    global_status_ptr& = 0
}

verify(.counter: $&Int32, .status: $&Int32) -> () := {
    puts(.string="Verifying resource\n")
    if counter& != 1 {
        status& = 7
        return
    }
}

main () -> (.status_code: Int32) := {
    counter :: Int32 = 0
    status_code = 9
    #defer verify(.counter=$&counter, .status=$&status_code)
    handle := Resource(.counter=$&counter, .status=$&status_code)
    if counter != 0 {
        status_code = 6
        return
    }
    status_code = 2
}
