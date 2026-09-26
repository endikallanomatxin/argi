main(.system: System = System()) -> (.status_code: Int32 = 0) := {
    assume stdout ::= system.terminal&.stdout_writer

    literal ::= from_literal(.data = "borrowed view")
    text ::= as_view(.self = literal)
    print(.value = text)
}
