square := (.value: Int32) -> (.result: Int32) {
    result = value * value
}

identity := <.T: Type> (.value: T) -> (.result: T) {
    result = value
}

main := () -> (.status_code: Int32 = 0) {
    if square(7).result != 49 { abort }
    if identity<Int32>(42).result != 42 { abort }
    if identity<UInt8>(7).result != 7 { abort }
}
