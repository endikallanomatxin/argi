Widget : Type = (.value: Int32)

init(.p: $&Widget, .fail: Bool) -> (.result: Errable#(.t: Void, .reasons: (..rejected))) := {
    if fail {
        result = ..error(.reason = ..rejected)
        return
    }
    p& = (.value = 42)
    result = ..ok Void()
}

main() -> (.status_code: Int32) := {
    failed ::= Widget(.fail = true)
    match failed {
        ..error _ { }
        ..ok _ {
            status_code = 2
            return
        }
    }
    constructed ::= Widget(.fail = false)
    match constructed {
        ..ok value { status_code = value.value - 42 }
        ..error _ { status_code = 1 }
    }
}
