Source#(.Participant: Type): Contract = (
    .read: (.self: &Participant) -> (.result: Int32) where {}
)
Box := (.value: Int32)
implement Source#(Box) (.read = read_box)
read_box := (.self: &Box) -> (.result: Int32) { result = self&.value }
initialize := (.box: $&Box, .output: $&Virtual#(Source), .initialize: Bool) -> () {
    if initialize { box& = Box(42) }
    output& = Virtual#(Source)(box)
}
main := () -> (.status_code: Int32 = 0) {
    box :: Box
    source :: Virtual#(Source)
    initialize($&box, $&source, false)
    if read(&source) != 42 { abort }
}
