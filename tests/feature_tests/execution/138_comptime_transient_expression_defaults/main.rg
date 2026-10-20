record_width#(.T: Type) := () -> (.count: UIntNative) { count = size_of(.type = T) }

read_default#(.T: Type) := (.value: T) -> (.result: Int32) {
    #if record_width#(.T: T)() > 0 { result = value.extra } #else { result = 0 }
}

extra#(.n: Int32) := () -> (.result: Int32) { result = n + 2 }

with_default#(.T: Type, .n: Int32) := (.value: T) -> (.result: Int32) {
    result = read_default#(.T: (.item: T, .extra: Int32 = extra#(.n = n)()))(
        .value = (.item = value)
    )
}

main() -> (.status_code: Int32) := {
    if with_default#(.T: Int32, .n = 40)(.value = 7) != 42 { abort }
    if with_default#(.T: Bool, .n = 39)(.value = true) != 41 { abort }
    if [#run with_default#(.T: Int32, .n = 40)(.value = 9)] != 42 { abort }
    status_code = 42
}
