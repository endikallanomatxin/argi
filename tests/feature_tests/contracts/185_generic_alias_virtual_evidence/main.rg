Readable#(.Source: Type): Contract = (
    .read : (.source: &Source) -> (.result: Int32) where {}
)

Box := #(.T: Type) (.value: T)

read_box := #(.T: Type) (.source: &Box#(T)) -> (.result: Int32) {
    result = source&.value
}

implement Readable#(Box#(Int32)) (.read = read_box)

main := () -> (.status_code: Int32 = 0) {
    box ::= Box#(Int32)(.value = 42)
    erased ::= to_virtual#(.contract: Readable)(.value = &box)
    if Readable#().read(&erased).result != 42 { abort }
}
