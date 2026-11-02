Empty: Type = ()

Record := (.empty: Empty, .value: Int32)

Batch := (.items: [2]Record)

read := (.record: Record) -> (.value: Int32) { value = record.value }

make := () -> (.record: Record) { record = (.empty = (), .value = 20) }

empty_array := (.value: [0]Int32) -> () {}

empty_generic := #(.Element: Type) (.sample: Element) -> (.value: Empty) { value = () }

main := () -> (.status_code: Int32 = 0) {
    empty :: [0]Int32 = ()
    empty_array(.value = empty)
    empty_array(.value = ())
    generic ::= empty_generic#(.Element: Int32)(.sample = 1)
    generic_copy :: Empty = generic
    batch :: Batch = (.items = ((.empty = (), .value = 1), (.empty = (), .value = 2)))
    batch.items[0] = (.empty = (), .value = 20)
    batch.items[1].empty = ()
    made ::= make()
    status_code = [
        read(.record = (.empty = (), .value = batch.items[0].value))
        + made.value
        + batch.items[1].value
    ]
}
