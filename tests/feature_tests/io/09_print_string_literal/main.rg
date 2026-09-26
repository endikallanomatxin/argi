main(.system: System) -> (.status_code: Int32 = 0) := {
    assume stdout ::= system.terminal&.stdout_writer

    print(.value = "literal output")
}
