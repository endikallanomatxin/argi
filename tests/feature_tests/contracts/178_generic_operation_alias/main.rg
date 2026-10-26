Readable<.T: Type>: Contract = (
    .Item : Type
    .read : (.value: &T) -> (.result: Item)
)

Box := <.T: Type> (.value: T)

read_box := <.T: Type> (.value: &Box<T>) -> (.result: T) {
    result = value&.value
}

implement<.T: Type> Readable<Box<T>> (
    .Item : Type = T
    .read = read_box
)

main := () -> (.status_code: Int32 = 0) {
    box ::= Box<Int32>(.value = 42)
    if read(&box).result != 42 { abort }
    other ::= Box<UInt8>(.value = 7)
    if Readable<Box<UInt8>>.read(&other).result != 7 { abort }
}
