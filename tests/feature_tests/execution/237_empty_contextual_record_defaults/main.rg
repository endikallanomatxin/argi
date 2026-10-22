main() -> (.status_code: Int32) := {
    first: (.answer: Int32 = 20) = ()
    second: (.answer: Int32 = 22) = ()
    status_code = first.answer + second.answer
}
