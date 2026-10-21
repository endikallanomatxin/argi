calculate#(.T: Type, .n: Int32) := () -> (.result: T) {
    result = #run () -> (.value: T) { value = n }
}

selected#(.n: Int32) := () -> (.result: Int32) {
    result = #run () -> (.value: Int32) {
        #if n == 42 {
            value = #run () -> (.inner: Int32) { inner = n }
        } #else {
            value = 41
        }
    }
}

captured_local#(.n: Int32) := () -> (.result: Int32) {
    local: Int32 = n
    result = #run () -> (.value: Int32) {
        value = #run () -> (.inner: Int32) { inner = local }
    }
}

nested_specialization#(.n: Int32) := () -> (.result: Int32) {
    result = #run () -> (.value: Int32) {
        value = identity#(.n = #run () -> (.inner: Int32) { inner = n })()
    }
}

identity#(.n: Int32) := () -> (.result: Int32) { result = n }

Items#(.n: Int32): Type = (.items: Array#(.n = n, .t: Int32))

read_items#(.n: Int32) := () -> (.result: Int32) {
    values: Items#(.n = #run () -> (.count: Int32) { count = n }) = (.items = (20, 22))
    result = values.items[0] + values.items[1]
}

forward#(.n: Int32) := () -> (.result: Int32) {
    result = identity#(.n = #run () -> (.value: Int32) { value = n })()
}

main() -> (.status_code: Int32) := {
    if captured_local#(.n = 41)() != 41 { abort }
    if captured_local#(.n = 42)() != 42 { abort }
    if nested_specialization#(.n = 41)() != 41 { abort }
    if nested_specialization#(.n = 42)() != 42 { abort }
    if read_items#(.n = 2)() != 42 { abort }
    if forward#(.n = 41)() != 41 { abort }
    if forward#(.n = 42)() != 42 { abort }
    if calculate#(.T: Int8, .n = 41)() != 41 { abort }
    if calculate#(.T: Int32, .n = 41)() != 41 { abort }
    if selected#(.n = 41)() != 41 { abort }
    if selected#(.n = 42)() != 42 { abort }
    status_code = calculate#(.T: Int32, .n = 42)()
}
