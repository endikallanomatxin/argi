-- Minimal array abstraction; functionality will be expanded in the future.
Array#(.t: Type) : Type = (
    .data: $&Any,
    .length: Int32 = 0,
)

length (.array: Array#(.t)) -> (.value: Int32) := {
    value = array.length
}

data_pointer (.array: Array#(.t)) -> (.pointer: $&Any) := {
    pointer = array.data
}
