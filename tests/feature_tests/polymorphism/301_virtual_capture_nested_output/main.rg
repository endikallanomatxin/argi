Source#(.Participant: Type): Contract = (
    .read: (.self: &Participant) -> (.result: Int32) where {}
)
Box := (.value: Int32)
Wrapper := (.source: Virtual#(Source))
implement Source#(Box) (.read = read_box)
read_box := (.self: &Box) -> (.result: Int32) { result = self&.value }
initialize := (.box: $&Box, .output: $&Wrapper) -> () {
    box& = Box(42)
    output& = Wrapper(Virtual#(Source)(box))
}
main := () -> (.status_code: Int32 = 0) {
    box :: Box
    source :: Wrapper
    initialize($&box, $&source)
    if read(&source.source) != 42 { abort }
}
