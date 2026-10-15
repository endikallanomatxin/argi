main() -> (.status_code: Int32) := {
    value :: Int32 = 7
    borrowed_view ::= single_mutable_array_view#(.t: Int32)(.data = $&value, .length = 100000)
    status_code = 0
}
