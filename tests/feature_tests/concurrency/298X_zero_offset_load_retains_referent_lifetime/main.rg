replace := (.slot: $&&Int32, .value: &Int32) -> () { slot& = value }

load := (.slot: &&Int32) -> (.result: &Int32) {
    same := trusted_reference_offset#(.t: &Int32)(.base = slot, .elements = 0).reference
    result = same&
}

forward_load := (.slot: &&Int32) -> (.result: &Int32) {
    result = load(.slot = slot)
}

main := () -> () {
    value: Int32 = 7
    selected :: &Int32 = &value
    {
        original: Int32 = 9
        slot :: &Int32 = &value
        replace(.slot = $&slot, .value = &original)
        selected = forward_load(.slot = &slot)
    }
    if selected& != 7 { abort }
}
