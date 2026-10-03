main() -> (.status_code: Int32 = 0) := {
    duration ::= Duration(.nanoseconds = 1)
    duration._nanoseconds = 2
}
