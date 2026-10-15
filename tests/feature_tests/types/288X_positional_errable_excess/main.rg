Reasons: Type = (..unavailable)

run_main() -> (.result: Errable#(Void, Reasons, Int32)) := {
    result = ..ok Void()
}

main#(.WriterType: Type: Writer#(WriterType))(.writer: $&WriterType = reach writer) -> (.status_code: Int32 = 1) := {
    run_main()!!!
    status_code = 0
}
