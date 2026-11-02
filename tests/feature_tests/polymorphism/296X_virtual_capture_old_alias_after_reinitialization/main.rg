Source#(.Participant: Type): Contract = (
    .read: (.self: &Participant) -> (.result: Int32) where {}
)
Box := (.value: Int32)
implement Deinit#(Box) (.deinit = (.self: $&Box) -> () {})
implement Source#(Box) (.read = read_box)
read_box := (.self: &Box) -> (.result: Int32) { result = self&.value }
initialize := (.box: $&Box, .output: $&Virtual#(Source)) -> () {
    box& = Box(42)
    output& = to_virtual#(Source)(box)
}
main := () -> (.status_code: Int32 = 0) {
    box :: Box
    source :: Virtual#(Source)
    initialize($&box, $&source)
    old ::= source
    initialize($&box, $&source)
    if read(&old) != 42 { abort }
}
