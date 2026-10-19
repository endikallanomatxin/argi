Cell: Type = (.value: Int32)

Empty: Type = ()

Box#(.T: Type): Type = (.value: T)

width#(.T: Type) := () -> (.count: UIntNative) { count = size_of(.type = T) }

choose#(.T: Type) := (.value: T) -> (.result: Int32) {
    #if width#(.T: T)() > 0 { result = 42 } #else { result = 0 }
}

pointer#(.T: Type) := (.value: T) -> (.result: Int32) {
    result = choose#(.T: &T)(.value = &value)
}

array#(.T: Type) := (.value: T) -> (.result: Int32) {
    result = choose#(.T: [2]T)(.value = (value, value))
}

record#(.T: Type) := (.value: T) -> (.result: Int32) {
    result = choose#(.T: (.item: T))(.value = (.item = value))
}

nominal#(.T: Type) := (.value: T) -> (.result: Int32) {
    result = choose#(.T: Box#(T))(.value = (.value = value))
}

main := () -> (.status_code: Int32) {
    cell :: Cell = (.value = 1)
    empty :: Empty = ()
    if pointer(.value = cell) != 42 { abort }
    if array(.value = cell) != 42 { abort }
    if record(.value = cell) != 42 { abort }
    if record(.value = empty) != 0 { abort }
    if array(.value = empty) != 0 { abort }
    status_code = nominal(.value = cell)
}
