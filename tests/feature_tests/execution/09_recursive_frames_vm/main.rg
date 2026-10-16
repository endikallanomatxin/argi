Pair: Type = (.left: Int32, .right: Int32)

recurse(.remaining: Int32) -> (.result: Pair = (.left = 20, .right = 22)) := {
    if remaining > 0 { result = recurse(.remaining = remaining - 1) }
}

main() -> (.status_code: Int32 = 0) := {
    pair ::= recurse(.remaining = 32)
    status_code = pair.left + pair.right
}
