..missing

attempt() -> (.result: Errable#(Void, (..missing))) := {
    result = ..error(.reason = ..missing)
}

main(.writer: $&Writer = reach writer) -> () := {
    attempt()!!!
    abort
}
