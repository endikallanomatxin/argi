Result: Type = (..ok(.value: Int32), ..empty)

select(.value: $&Result, .calls: $&Int32) -> (.result: $&Result) := {
    calls&= calls&+ 1
    result = value
}

main() -> (.status_code: Int32) := {
    value :: Result = ..ok(.value = 41)
    calls :: Int32 = 0
    selected ::= select(.value = $&value, .calls = $&calls)
    if selected&== ..ok {
        payload ::= $&selected&..ok
        payload&.value = payload&.value + 1
    } else {
        abort
    }
    if calls != 1 { abort }
    if value == ..ok { status_code = value ..ok.value } else { abort }
}
