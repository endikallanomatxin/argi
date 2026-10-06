work() -> !Void = ..ok Void() := {}
run_main() -> !Void = ..ok Void() := {
    work()!
}

main(.writer: $&Writer = reach writer) -> (.status_code: Int32 = 1) := {
    run_main()!!!
    status_code = 0
}
