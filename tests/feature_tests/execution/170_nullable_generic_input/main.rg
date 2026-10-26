select_nullable := <.T: Type> (.value: ?T, .fallback: T) -> (.result: T) {
    match value {
        ..some payload { result = payload.value }
        ..none { result = fallback }
    }
}

computed := () -> (.result: Int32) {
    value: ?Int32 = ..some(.value = 42)
    result = select_nullable(.value = value, .fallback = 0)
}

main := () -> (.status_code: Int32) {
    value: ?UIntNative = ..some(.value = 42)
    absent: ?UIntNative = ..none
    zero: UIntNative = 0
    answer: UIntNative = 42
    if select_nullable<.T: UIntNative>(.value = value, .fallback = zero) != 42 { abort }
    if select_nullable(.value = value, .fallback = zero) != 42 { abort }
    if select_nullable(.value = absent, .fallback = answer) != 42 { abort }
    flag: ?Bool = ..some(.value = true)
    if select_nullable(.value = flag, .fallback = false) == false { abort }
    if #run () -> (.value: Int32) { value = computed() } != 42 { abort }
    status_code = 42
}
