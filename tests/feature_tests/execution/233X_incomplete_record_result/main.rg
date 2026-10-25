Pair: Type = (.left: Int32, .right: Int32)

make_pair() -> (.result: Pair) := { result = (.left = 42) }

main() -> (.status_code: Int32) := {
    pair ::= make_pair()
    status_code = pair.left
}
