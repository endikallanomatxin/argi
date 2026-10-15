add_one(.i: Int32) -> (.o: Int32) := {
    o = i + 1
}

main() -> (.status_code: Int32) := {
    status_code = 40 | add_one(_ + 1)
}
