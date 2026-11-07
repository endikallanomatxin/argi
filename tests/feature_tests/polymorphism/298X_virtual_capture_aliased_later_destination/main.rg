Source#(.Participant: Type): Contract = (
    .read: (.self: &Participant) -> (.result: Int32) where {}
)
Box := (.value: Int32)
implement Source#(Box) (.read = read_box)
read_box := (.self: &Box) -> (.result: Int32) { result = self&.value }
initialize := (.box: $&Box, .output: $&Virtual#(Source), .other: $&Box) -> () {
    box& = Box(42)
    output& = Virtual#(Source)(box)
    other& = Box(99)
}
main := () -> (.status_code: Int32 = 0) {
    box :: Box
    source :: Virtual#(Source)
    initialize($&box, $&source, $&box)
    if read(&source) != 42 { abort }
}
