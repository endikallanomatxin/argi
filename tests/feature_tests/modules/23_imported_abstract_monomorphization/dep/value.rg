ExampleAbstract#(.Value: Type): Contract = (
    .value_code: (.value: Value) -> (.r: Int32)
)

_int_code := (.value: Int32) -> (.r: Int32) { r = 1 }
_char_code := (.value: Char) -> (.r: Int32) { r = 2 }

implement ExampleAbstract#(Int32) (.value_code = _int_code)
implement ExampleAbstract#(Char) (.value_code = _char_code)

use_value#(.Value: Type: ExampleAbstract) := (.value: Value) -> (.status_code: Int32) {
    status_code = value_code(.value = value).r
}
