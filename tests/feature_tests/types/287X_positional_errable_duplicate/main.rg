run_main() -> (.result: Errable#(Void, .t: Int32)) := {
    result = ..ok Void()
}

main(.writer: $&Writer = reach writer) -> (.status_code: Int32 = 1) := {
    run_main()!!!
    status_code = 0
}
