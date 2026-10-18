locations := () -> (.result: Int32) {
    first ::= error_location_id()
    second ::= error_location_id()
    if first.value == second.value { abort }
    first_source ::= source_location(first)
    second_source ::= source_location(second)
    if first_source.line == second_source.line { abort }
    if second_source.column != first_source.column + 1 { abort }
    if first_source.source_line&!= 32 { abort }
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
