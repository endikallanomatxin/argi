Readable<.Value: Type>: Contract = (
    .Item  : Type
    .Count : Int
    .read  : (.self: &Value) -> (.value: Item) where {}
)

Integer := (.value: Int32)

Floating := (.value: Float64)

_read_integer := (.self: &Integer) -> (.value: Int32) { value = self&.value }

_read_floating := (.self: &Floating) -> (.value: Float64) { value = self&.value }

implement Readable<Integer> (.Item: Type = Int32, .Count: Int = 1, .read = _read_integer)

implement Readable<Floating> (.Item: Type = Float64, .Count: Int = 2, .read = _read_floating)

main := (.system: System) -> (.status_code: Int32 = 0) {
    integer ::= Integer(17)
    floating ::= Floating(2.5)
    left ::= to_virtual<.contract: Readable<.Item: Int32, .Count = 1>>(.value = &integer)
    right ::= to_virtual<.contract: Readable<.Count = 2, .Item: Float64>>(.value = &floating)
    if read(.self = &left) != 17 { status_code = 1 }
    if read(.self = &right) != 2.5 { status_code = 2 }
}
