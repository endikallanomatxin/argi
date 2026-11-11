Box := (.reference: &Int32)
retarget := (.box: $&Box, .replacement: &Int32) -> () { box&.reference = replacement }
extract := (.box: Box, .replacement: &Int32, .select: Bool) -> (.result: &Int32) {
    first ::= box
    second ::= box
    targets: [2] $&Box = ($&first, $&second)
    retarget(.box = targets[0], .replacement = replacement)
    result = first.reference
}
main := (.system: System) -> () {
    early: Int32 = 7
    pointer :: &Int32 = &early
    {
        later: Int32 = 42
        pointer = extract(.box = Box(&early), .replacement = &later, .select = true)
    }
    _ = pointer&
}
