main(.system: System = System()) -> (.status_code: Int32 = 0) := {
    literal ::= from_literal(.data = "error view")
    literal_ptr ::= pointer(.self = &literal)
    text : StringView = (
        .data = cast#(.to: UIntNative)(.value = literal_ptr),
        .length = 10,
    )
    print_error(text)
}
