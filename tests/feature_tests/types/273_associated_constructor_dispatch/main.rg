Box := #(.t: Type) (.value: t, .tag: Int32)

BoxInitArgs: Type = #(.t: Type) (.value: t, .tag: Int32 = 1)

implement#(.t: Type) Init#(Box#(.t: t), BoxInitArgs#(t)) (
    .Result : Type = Box#(.t: t)

    .init = BoxInitArgs#(t) -> (.result: Result) {
        _init_value ::= ~value
        _init_tag ::= ~tag

        result = (.value = _init_value, .tag = _init_tag)
    }
)

Other := #(.t: Type) (.value: t)

OtherInitArgs2: Type = #(.t: Type) (.value: t)

implement#(.t: Type) Init#(Other#(.t: t), OtherInitArgs2#(t)) (
    .Result : Type = Other#(.t: t)

    .init = OtherInitArgs2#(t) -> (.result: Result) {
        _init_value ::= ~value

        result = (.value = _init_value)
    }
)

Record := (.tag: Int32)

RecordInitArgs3: Type = #(.sample: Type) (.value: sample)

implement#(.sample: Type) Init#(Record, RecordInitArgs3#(sample)) (
    .Result : Type = Record

    .init = RecordInitArgs3#(sample) -> (.result: Result) {
        _init_value ::= ~value

        _ ::= _init_value
        result = (.tag = 42)
    }
)

main := () -> (.status_code: Int32) {
    first ::= Box#(.t: Int32)(.value = 4)
    second ::= Box(.value = 'a', .tag = 7)
    other ::= Other(.value = 9)
    record ::= Record(.value = 'b')
    if [
        first.value != 4
        or first.tag != 1
        or second.value != 'a'
        or second.tag != 7
        or other.value != 9
        or record.tag != 42
    ] {
        status_code = 1
        return
    }
    status_code = 0
}
