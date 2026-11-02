Source#(.Participant: Type): Contract = (
    .read: (.self: &Participant) -> (.result: Int32) where {}
)
Box := (.value: Int32)
implement Source#(Box) (.read = read_box)
read_box := (.self: &Box) -> (.result: Int32) { result = self&.value }
initialize := (.box: $&Box, .output: $&Virtual#(Source)) -> () {
    box& = Box(42)
    output& = to_virtual#(Source)(box)
}
forward := #(.T: Type)(.box: $&Box, .output: $&Virtual#(Source)) -> () {
    initialize(box, output)
}
main := () -> (.status_code: Int32 = 0) {
    box :: Box
    source :: Virtual#(Source)
    forward#(Int32)($&box, $&source)
    if read(&source) != 42 { abort }
}
