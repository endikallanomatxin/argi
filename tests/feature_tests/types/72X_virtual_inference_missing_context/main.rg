Counter : Abstract = (bump(.self: $&Self) -> ())
Other : Abstract = ()
Probe : Type = (.value: UIntNative = 0)
Probe implements Counter
Probe implements Other
bump(.self: $&Probe) -> () := { self&.value = self&.value + 1 }
main() -> (.status_code: Int32) := {
    probe ::= Probe()
    handle ::= to_virtual($&probe)
    status_code = 0
}
