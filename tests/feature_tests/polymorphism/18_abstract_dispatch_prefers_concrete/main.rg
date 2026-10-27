ExampleAbstract#(.Value: Type): Contract = (
    .pick : (.value: Value) -> (.status_code: Int32)
)

_generic_pick := #(.Value: Type) (.value: Value) -> (.status_code: Int32) { status_code = 1 }

_int_pick := (.value: Int32) -> (.status_code: Int32) { status_code = 2 }

implement#(.Value: Type) ExampleAbstract#(Value) (.pick = _generic_pick)

implement ExampleAbstract#(Int32) (.pick = _int_pick)

main := () -> (.status_code: Int32) { status_code = pick(.value = 123) }
