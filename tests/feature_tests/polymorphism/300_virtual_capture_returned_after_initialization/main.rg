Source#(.Participant: Type): Contract = (
    .read: (.self: &Participant) -> (.result: Int32) where {}
)
Box := (.value: Int32)
implement Source#(Box) (.read = read_box)
read_box := (.self: &Box) -> (.result: Int32) { result = self&.value }
initialize := (.box: $&Box) -> (.result: Virtual#(Source)) {
    box& = Box(42)
    result = to_virtual#(Source)(box)
}
main := () -> (.status_code: Int32 = 0) {
    box :: Box
    source ::= initialize($&box).result
    if read(&source) != 42 { abort }
}
