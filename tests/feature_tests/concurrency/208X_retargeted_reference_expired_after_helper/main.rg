Box := (.reference: &Int32)
choose := (.first: $&Box, .second: $&Box, .select: Bool) -> (.result: $&Box) {
    if select { result = first } else { result = second }
}
retarget := (.box: $&Box, .replacement: &Int32) -> () { box&.reference = replacement }
extract := (.box: Box, .replacement: &Int32, .select: Bool) -> (.result: &Int32) {
    first ::= box
    second ::= box
    target ::= choose(.first = $&first, .second = $&second, .select = select)
    retarget(.box = target, .replacement = replacement)
    result = first.reference
}
main := (.system: System) -> () {
    early: Int32 = 7
    pointer: &Int32
    {
        later: Int32 = 42
        pointer = extract(.box = Box(&early), .replacement = &later, .select = true)
    }
    _ = pointer&
}
