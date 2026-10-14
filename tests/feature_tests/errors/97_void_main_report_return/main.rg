..missing

attempt() -> (.result: Errable#(Void, (..missing))) := {
    result = ..error(.reason = ..missing)
}

main#(.WriterType: Type: Writer#(WriterType))(.writer: $&WriterType = reach writer) -> () := {
    attempt()!!!
    abort
}
