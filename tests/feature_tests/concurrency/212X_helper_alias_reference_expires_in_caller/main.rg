Box := (.reference: &Int32)
Handle := (.target: $&Box)
choose := (.first: $&Box, .second: $&Box, .select: Bool) -> (.result: $&Box) {
    if select { result = first } else { result = second }
}
retarget := (.box: $&Box, .replacement: &Int32) -> () { box&.reference = replacement }
main := (.system: System) -> () {
    early: Int32 = 7
    first ::= Box(&early)
    second ::= Box(&early)
    {
        later: Int32 = 42
        target ::= choose(.first = $&first, .second = $&second, .select = true)
        retarget(.box = target, .replacement = &later)
    }
    _ = first.reference&
}
