Source#(.Participant: Type): Contract = (
    .read: (.self: &Participant) -> (.result: Int32) where {}
)
Resource := (.value: Int32)
implement Deinit#(Resource) (.deinit = (.self: $&Resource) -> () {})
Box := (.value: &Resource)
implement Source#(Box) (.read = read_box)
read_box := (.self: &Box) -> (.result: Int32) { result = self&.value&.value }
initialize := (.box: $&Box, .output: $&Virtual#(Source), .value: &Resource) -> () {
    box& = Box(value)
    output& = to_virtual#(Source)(box)
}
main := () -> (.status_code: Int32 = 0) {
    value ::= Resource(42)
    box :: Box
    source :: Virtual#(Source)
    initialize($&box, $&source, &value)
    deinit($&value)
    if read(&source) != 42 { abort }
}
