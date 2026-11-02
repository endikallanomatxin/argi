Selection#(.Number: Type): Contract = (
    .Tag    : Type
    .select : (.tag: Tag, .number: Number) -> (.value: Int32)
)

First: Type = (..before, ..shared, ..payload Int32)

Second: Type = (..shared, ..after, ..payload Int32)

_first_select := (.tag: First, .number: Int32) -> (.value: Int32) {
    if tag != ..shared { abort }
    value = number
}

_second_select := (.tag: Second, .number: UInt32) -> (.value: Int32) {
    if tag != ..shared { abort }
    value = 2
}

implement Selection#(Int32) (.Tag: Type = First, .select = _first_select)

implement Selection#(UInt32) (.Tag: Type = Second, .select = _second_select)

with_payload := (.tag: First) -> (.value: Int32) {
    match tag {
        ..payload data { value = data }
        ..before { abort }
        ..shared { abort }
    }
}

with_second_payload := (.tag: Second) -> (.value: Int32) {
    match tag {
        ..payload data { value = data }
        ..shared { abort }
        ..after { abort }
    }
}

main := () -> (.status_code: Int32 = 0) {
    signed: Int32 = 1
    unsigned: UInt32 = 1
    if select(.tag = ..shared, .number = signed) != 1 { abort }
    if select(.tag = ..shared, .number = unsigned) != 2 { abort }
    if with_payload(.tag = ..payload 7) != 7 { abort }
    if with_second_payload(.tag = ..payload 9) != 9 { abort }
}
