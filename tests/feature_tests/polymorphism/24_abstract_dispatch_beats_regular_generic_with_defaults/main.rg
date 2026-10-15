Selection#(.Value: Type): Contract = (
    .pick: (.value: Value, .bonus: Int32 = 1) -> (.status_code: Int32)
)
_generic_pick#(.Value: Type) := (.value: Value, .bonus: Int32 = 1) -> (.status_code: Int32) {
    status_code = 2
}
_int_pick := (.value: Int32, .bonus: Int32 = 1) -> (.status_code: Int32) { status_code = bonus }
implement#(.Value: Type) Selection#(Value) (.pick = _generic_pick)
implement Selection#(Int32) (.pick = _int_pick)
main := () -> (.status_code: Int32) { status_code = pick(.value = 7) }
