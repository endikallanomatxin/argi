main() -> (.status_code: Int32) := {
    element :: Int32 = 1
    view ::= _trusted_array_view#(.t: Int32)(.data = $&element, .length = 1000)
    status_code = get(.self = &view, .index = 900).result..ok
}
