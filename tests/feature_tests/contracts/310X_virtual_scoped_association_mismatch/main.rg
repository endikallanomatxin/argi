Readable#(.Value: Type): Contract = (
    .Item  : Type
    .Count : Int
    .read  : (.self: &Value) -> (.value: Item) where {}
)

Integer := (.value: Int32)

Floating := (.value: Float64)

_read_integer := (.self: &Integer) -> (.value: Int32) { value = self&.value }

_read_floating := (.self: &Floating) -> (.value: Float64) { value = self&.value }

implement Readable#(Integer) (.Item: Type = Int32, .Count: Int = 1, .read = _read_integer)

implement Readable#(Floating) (.Item: Type = Float64, .Count: Int = 2, .read = _read_floating)

main := (.system: System) -> () {
    integer ::= Integer(17)
    erased ::= to_virtual#(.contract: Readable#(.Item: Float64, .Count = 1))(.value = &integer)
}
