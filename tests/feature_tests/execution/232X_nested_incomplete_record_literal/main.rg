Pair: Type = (.left: Int32, .right: Int32)

Container: Type = (.pair: Pair, .ready: Bool)

main() -> (.status_code: Int32) := {
    value: Container = (.pair = (.left = 42), .ready = true)
    status_code = value.pair.left
}
