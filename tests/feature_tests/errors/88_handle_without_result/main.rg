..missing
handled :: Int32 = 0
drops :: Int32 = 0
calls :: Int32 = 0

Owner: Type = (.value: Int32)

Owner deinit(.self: $&Owner) -> () := { drops = drops + 1 }

attempt(.fail: Bool) -> (.result: Errable#(Owner, (..missing))) := {
    calls = calls + 1
    if fail { result = ..error(.reason = ..missing) } else { result = ..ok Owner(7) }
}

discard#(.t: Type)(.input: Errable#(t, (..missing)), .count: $&Int32) -> () := {
    ~input handle error {
        match error.reason { ..missing { count&= count&+ 1 } }
    }
}

early_return(.fail: Bool) -> (.result: Int32 = 5) := {
    attempt(fail) handle error {
        result = 9
        return
    }
    result = 6
}

propagate() -> (.result: Errable#(Void, (..missing))) := {
    attempt(true) handle error {
        attempt(true)!
    }
    result = ..ok Void()
}

recover_propagation() -> (.result: Errable#(Owner, (..missing))) := {
    recovered ::= attempt(true) handle error, value {
        attempt(true)!
        value = Owner(8)
    }
    result = ..ok ~recovered
}

main() -> (.status_code: Int32 = 0) := {
    attempt(false) handle error { handled = handled + 1 }
    if calls != 1 or handled != 0 or drops != 1 { abort }

    attempt(true) handle error { handled = handled + 1 }
    if calls != 2 or handled != 1 or drops != 1 { abort }

    discard#(.t: Owner)(attempt(false), $&handled)
    discard#(.t: Owner)(attempt(true), $&handled)
    if calls != 4 or handled != 2 or drops != 2 { abort }

    if early_return(true) != 9 or early_return(false) != 6 { abort }
    match propagate() { ..error _ {} ..ok _ { abort } }
    match recover_propagation() { ..error _ {} ..ok _ { abort } }

    previous_drops ::= drops
    index :: Int32 = 0
    while index < 3 {
        attempt(true) handle error {
            local ::= Owner(1)
            index = index + 1
            if index == 2 { break }
            continue
        }
        abort
    }
    if index != 2 or drops != previous_drops + 2 { abort }
}
