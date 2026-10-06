..missing
drops :: Int32 = 0

Owner: Type = (.value: Int32)

Owner deinit(.self: $&Owner) -> () := { drops = drops + 1 }

attempt(.fail: Bool) -> (.result: Errable#(Int32, (..missing))) := {
    if fail { result = ..error(.reason = ..missing) } else { result = ..ok 7 }
}

run(.fail: Bool, .writer: $&Writer = reach writer) -> (.result: Int32 = 9) := {
    local ::= Owner(1)
    value ::= attempt(fail)!!!
    result = value
}

unwrap#(
        .t : Type
    )(
        .input  : Errable#(t, (..missing)),
        .writer : $&Writer                  = reach writer
    ) -> (
        .result : Int32 = 9
    ) := {
    result = ~input!!!
}

main(.writer: $&Writer = reach writer) -> (.status_code: Int32 = 0) := {
    if unwrap#(.t: Int32)(attempt(false)) != 7 { abort }
    if unwrap#(.t: Int32)(attempt(true)) != 9 { abort }
    if run(false) != 7 or drops != 1 { abort }
    if run(true) != 9 or drops != 2 { abort }
}
