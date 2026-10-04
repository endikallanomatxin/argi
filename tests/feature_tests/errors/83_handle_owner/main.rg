..missing

Owner: Type = (.value: Int32)

Owner deinit(.self: $&Owner) -> () := { self&.value = 0 }

make(.fail: Bool) -> (.result: Errable#(.t: Owner, .reasons: (..missing))) := {
    if fail { result = ..error(.reason = ..missing) } else { result = ..ok(.value = 7) }
}

main() -> (.status_code: Int32 = 0) := {
    first ::= make(.fail = false) handle value, error { value = (.value = 9) }
    second ::= make(.fail = true) handle value, error { value = (.value = 9) }
    if first.value != 7 or second.value != 9 { abort }
}
