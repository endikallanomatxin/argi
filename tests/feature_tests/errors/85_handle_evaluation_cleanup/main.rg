..missing
calls :: Int32 = 0
drops :: Int32 = 0

Marker: Type = (.id: Int32)

Marker deinit(.self: $&Marker) -> () := { drops = drops + 1 }

attempt(.fail: Bool) -> !Int32 := {
    calls = calls + 1
    if fail { result = ..error(.reason = ..missing) } else { result = ..ok 5 }
}

recover(.fail: Bool) -> (.result: Int32) := {
    result = attempt(.fail = fail) handle value, error {
        marker ::= Marker(.id = 1)
        result = 12
        return
    }
}

main() -> (.status_code: Int32 = 0) := {
    if recover(.fail = false).result != 5 or calls != 1 or drops != 0 { abort }
    if recover(.fail = true).result != 12 or calls != 2 or drops != 1 { abort }
    handled ::= attempt(.fail = true) handle value, error {
        marker ::= Marker(.id = 2)
        value = 7
    }
    if handled != 7 or calls != 3 or drops != 2 { abort }
}
