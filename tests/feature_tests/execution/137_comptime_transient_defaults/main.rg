record_width := #(.T: Type) () -> (.count: UIntNative) { count = size_of(.type = T) }

read_default := #(.T: Type) (.value: T) -> (.result: Int32) {
    #if record_width#(.T: T)() > 0 {
        result = value.extra
    } #else {
        result = 0
    }
}

with_default := #(.T: Type) (.value: T) -> (.result: Int32) {
    result = read_default#(.T: (.item: T, .extra: Int32 = 42))(.value = (.item = value))
}

main := () -> (.status_code: Int32) {
    if with_default(.value = 7) != 42 { abort }
    if with_default(.value = true) != 42 { abort }
    if [#run () -> (.value: Int32) { value = with_default(.value = 9) }] != 42 { abort }
    status_code = 42
}
