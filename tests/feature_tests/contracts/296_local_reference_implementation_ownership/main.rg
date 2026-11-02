api := import ("./api")

Local := (.value: Int32)

Holder := #(.T: Type) (.value: T)

implement api.Inspect#(&Local) (
    .inspect = (.value: &Local) -> (.result: Int32) { result = value&.value }
)

implement api.Inspect#($&Local) (
    .inspect = (.value: $&Local) -> (.result: Int32) {
        value&.value = value&.value + 1
        result = value&.value
    }
)

implement#(.T: Type) api.Inspect#(&Holder#(T)) (
    .inspect = (.value: &Holder#(T)) -> (.result: Int32) { result = 19 }
)

main := () -> (.status_code: Int32 = 0) {
    local ::= Local(7)
    holder ::= Holder#(Int32)(.value = 3)
    if api.Inspect#(&Local).inspect(.value = &local).result != 7 { status_code = 1 }
    if api.Inspect#($&Local).inspect(.value = $&local).result != 8 { status_code = 2 }
    if local.value != 8 { status_code = 3 }
    if api.Inspect#(&Holder#(Int32)).inspect(.value = &holder).result != 19 { status_code = 4 }
}
