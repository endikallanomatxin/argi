Source#(.Participant: Type): Contract = (
    .read: (.self: &Participant) -> (.result: Int32) where {}
)
Box := (.value: Int32)
Wrapper := (.source: Virtual#(Source), .sentinel: Int32)
implement Source#(Box) (.read = read_box)
read_box := (.self: &Box) -> (.result: Int32) { result = self&.value }
initialize := (.box: $&Box, .output: $&Wrapper) -> () {
    box& = Box(42)
    output&.source = to_virtual#(Source)(box)
    output&.sentinel = 7
}
main := () -> (.status_code: Int32 = 0) {
    box :: Box
    source :: Wrapper
    initialize($&box, $&source)
    if read(&source.source) != 42 { abort }
    if source.sentinel != 7 { abort }
}
