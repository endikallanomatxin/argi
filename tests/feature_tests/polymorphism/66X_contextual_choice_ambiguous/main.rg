First: Type = (..before, ..shared)

Second: Type = (..shared, ..after)

FirstSelection#(.Number: Type): Contract = (
    .Tag    : Type
    .select : (.tag: Tag, .number: Number) -> (.value: Int32)
)

SecondSelection#(.Number: Type): Contract = (
    .Tag    : Type
    .select : (.tag: Tag, .number: Number) -> (.value: Int32)
)

_first_select := (.tag: First, .number: Int32) -> (.value: Int32) { value = 1 }

_second_select := (.tag: Second, .number: Int32) -> (.value: Int32) { value = 2 }

implement FirstSelection#(Int32) (.Tag: Type = First, .select = _first_select)

implement SecondSelection#(Int32) (.Tag: Type = Second, .select = _second_select)

main := () -> (.status_code: Int32 = 0) {
    number: Int32 = 1
    value := select(.tag = ..shared, .number = number)
}
