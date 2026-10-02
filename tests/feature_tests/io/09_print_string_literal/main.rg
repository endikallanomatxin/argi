main(.system: System) -> (.status_code: Int32 = 0) := {
    assume writer ::= $&system.terminal&.stdout

    print(.value = "literal output")
}
