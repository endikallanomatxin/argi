main() -> (.status_code: Int32 = 0) := {
    value :: Int32 = 2147483647
    wrapped ::= value + 1
    if wrapped != -2147483648 { abort }
    status_code = 42
}
