locations := () -> (.result: Int32) {
    first ::= error_location_id()
    second ::= error_location_id()
    if first.value == second.value { abort }
    result = 42
}

main := () -> (.status_code: Int32 = 0) {
    compiled ::= #run locations()
    if compiled != 42 { abort }
    #if locations() == 42 {
        status_code = locations()
    } else {
        abort
    }
}
