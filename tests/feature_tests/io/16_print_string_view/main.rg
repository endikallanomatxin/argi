main(.system: System) -> (.status_code: Int32 = 0) := {
    assume writer ::= $&system.terminal&.stdout

    literal ::= from_literal(.data = "string view output")
    text ::= as_view(.self = literal)
    print(.value = text)
}
