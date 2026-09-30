main(.system: System) -> (.status_code: Int32 = 0) := {
    address ::= _trusted_acquisition_subaddress(.base = 123, .address = 456).result
}
