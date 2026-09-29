Counter : Abstract = (bump(.self: $&Self) -> ())
Probe : Type = (.value: UIntNative = 0)
Probe implements Counter
bump(.self: $&Probe) -> () := { self&.value = self&.value + 1 }

escape() -> (.handle: $&Virtual#(.abstract: Counter)) := {
    handle = Probe() | to_virtual($&_) | $&_
}
main() -> (.status_code: Int32) := {
    handle ::= escape()
    bump(.self = handle)
    status_code = 0
}
