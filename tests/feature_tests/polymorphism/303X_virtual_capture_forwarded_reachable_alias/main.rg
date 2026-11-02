Source#(.Participant: Type): Contract = (
    .read: (.self: &Participant) -> (.result: Int32) where {}
)
Resource := (.value: Int32)
implement Deinit#(Resource) (.deinit = (.self: $&Resource) -> () {})
Storage := (.resource: &Resource)
Holder := (.target: &Storage)
Box := (.holder: &Holder)
implement Source#(Box) (.read = read_box)
read_box := (.self: &Box) -> (.result: Int32) {
    result = self&.holder&.target&.resource&.value
}
initialize := (.box: $&Box, .output: $&Virtual#(Source), .holder: &Holder, .other: $&Storage, .next: &Resource) -> () {
    box& = Box(holder)
    output& = to_virtual#(Source)(box)
    other& = Storage(next)
}
forward := (.box: $&Box, .holder: &Holder, .other: $&Storage, .next: &Resource) -> (.result: Int32) {
    source :: Virtual#(Source)
    initialize(box, $&source, holder, other, next)
    result = read(&source)
}
main := () -> () {
    first ::= Resource(42)
    second ::= Resource(99)
    storage ::= Storage(&first)
    holder ::= Holder(&storage)
    box :: Box
    value ::= forward($&box, &holder, $&storage, &second)
}
