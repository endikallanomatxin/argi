..startup_failed
fail() -> !Void := {
    result = ..error(.reason = ..startup_failed)
}
run_main() -> !Void = ..ok Void() := {
    fail() !! "starting application"
}

main#(.WriterType: Type: Writer#(WriterType))(.writer: $&WriterType = reach writer) -> (.status_code: Int32 = 1) := {
    run_main()!!!
    status_code = 0
}
