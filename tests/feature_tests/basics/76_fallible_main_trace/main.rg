..startup_failed
fail() -> !Void := {
    result = ..error(.reason = ..startup_failed)
}
run_main() -> !Void = ..ok Void() := {
    fail() !! "starting application"
}

main(.writer: $&Writer = reach writer) -> (.status_code: Int32 = 1) := {
    run_main()!!!
    status_code = 0
}
