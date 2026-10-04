..missing

attempt(.fail: Bool) -> (.result: Errable#(.t: Int32, .reasons: (..missing))) := {
    if fail { result = ..error(.reason = ..missing) } else { result = ..ok 7 }
}

recover#(.t: Type)(.input: Errable#(.t: t, .reasons: (..missing)), .fallback: t) -> (.result: t) := {
    result = ~input handle value, error {
        match error.reason { ..missing { value = ~fallback } }
    }
}

main() -> (.status_code: Int32 = 0) := {
    first ::= attempt(.fail = false) handle value, error {
        match error.reason { ..missing { value = 9 } }
    }
    second ::= attempt(.fail = true) handle value, error {
        match error.reason { ..missing { value = 9 } }
    }
    third ::= recover(.input = attempt(.fail = true), .fallback = 11).result
    if first != 7 or second != 9 or third != 11 { abort }
}
