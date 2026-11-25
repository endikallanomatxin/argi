Slot: Struct = (.reference: &Int32)
choose := (.flag: Bool, .first: $&Slot, .second: $&Slot) -> (.result: $&Slot) {
    if flag { result = first } else { result = second }
}
store := (.slot: $&Slot, .reference: &Int32) -> () {
    slot&.reference = reference
}
probe := (.flag: Bool) -> () {
    stable :: Int32 = 5
    first :: Slot = (.reference = &stable)
    second :: Slot = (.reference = &stable)
    replacement :: Int32 = 9
    chosen ::= choose(.flag = flag, .first = $&first, .second = $&second)
    store(.slot = chosen, .reference = &replacement)
    if flag {
        if first.reference& != 9 or second.reference& != 5 { abort }
    } else {
        if first.reference& != 5 or second.reference& != 9 { abort }
    }
}
main := () -> () {
    probe(.flag = true)
    probe(.flag = false)
}
