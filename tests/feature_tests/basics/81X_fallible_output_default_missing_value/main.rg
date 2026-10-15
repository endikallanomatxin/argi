run_main() -> !Void = := {}

main#(.WriterType: Type: Writer#(WriterType))(.writer: $&WriterType = reach writer) -> (.status_code: Int32 = 1) := {
    run_main()!!!
    status_code = 0
}
