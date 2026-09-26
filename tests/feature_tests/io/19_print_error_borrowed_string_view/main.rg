main(.system: System = System()) -> (.status_code: Int32 = 0) := {
    assume stderr ::= system.terminal&.stderr_file

    literal ::= from_literal(.data = "borrowed err")
    text ::= as_view(.self = literal)
    print_error(.value = text)
}
