copy_value(.value: Int32) -> (.result: Int32 = value) := {}

calculate#(.T: Type, .n: Int32) := () -> (.result: T) {
    result = #run (.system: System) -> (.value: T) { value = n }
}

selected#(.n: Int32) := () -> (.result: Int32) {
    result = #run (.system: System) -> (.value: Int32) {
        #if n == 42 {
            value = #run (.system: System) -> (.inner: Int32) { inner = n }
        } #else {
            value = 41
        }
    }
}

captured_local#(.n: Int32) := () -> (.result: Int32) {
    local := copy_value(.value = n)
    offset := 0
    result = #run (.system: System) -> (.value: Int32) {
        value = #run (.system: System) -> (.inner: Int32) { inner = local + offset }
    }
}

selected_capture#(.n: Int32) := (.runtime_value: Int32) -> (.result: Int32) {
    selector := copy_value(.value = n)
    result = #run (.system: System) -> (.value: Int32) {
        #if selector == 42 { value = n } #else { value = runtime_value }
    }
}

nested_specialization#(.n: Int32) := () -> (.result: Int32) {
    result = #run (.system: System) -> (.value: Int32) {
        value = identity#(.n = #run (.system: System) -> (.inner: Int32) { inner = n })()
    }
}

identity#(.n: Int32) := () -> (.result: Int32) { result = n }

Items#(.n: Int32): Type = (.items: Array#(.n = n, .t: Int32))

read_items#(.n: Int32) := () -> (.result: Int32) {
    values: Items#(.n = #run (.system: System) -> (.count: Int32) { count = n }) = (
        .items = (20, 22)
    )
    result = values.items[0] + values.items[1]
}

forward#(.n: Int32) := () -> (.result: Int32) {
    result = identity#(.n = #run (.system: System) -> (.value: Int32) { value = n })()
}

record_default(.system: System, .value: Int32) -> (.result: Int32) := {
    system.args&.count = system.args&.count + 1
    result = value
}

default_host#(.n: Int32) := () -> (.result: Int32) {
    result = #run (.system: System) -> (
        .value : Int32 = record_default(.system = system, .value = n)
    ) {
        if system.args&.count != 1 { abort }
    }
}

tuple_host#(.n: Int32) := () -> (.result: Int32) {
    pair ::= #run (.system: System) -> (.left: Int32 = n, .right: Int32 = 1) {}
    result = pair.left + pair.right
}

allocate_host#(.n: Int32) := () -> (.result: Int32) {
    result = #run (.system: System) -> (.value: Int32) {
        tracer :: NoopErrorTracer = (.marker = 0)
        erased ::= to_virtual#(.contract: ErrorTracer)(.value = $&tracer)
        assume error_tracer ::= $&erased
        assume allocator ::= $&CAllocator(.ffi = system.ffi)
        text ::= unwrap_or_abort(.value = String(.length = 3))
        value = n
    }
}

abort_host#(.n: Int32) := () -> (.result: Int32) {
    result = #run (.system: System) -> (.value: Int32) {
        tracer :: NoopErrorTracer = (.marker = 0)
        erased ::= to_virtual#(.contract: ErrorTracer)(.value = $&tracer)
        assume error_tracer ::= $&erased
        assume allocator ::= $&CAllocator(.ffi = system.ffi)
        text ::= unwrap_or_abort(.value = String(.length = 3))
        if n == 42 { abort }
        value = n
    }
}

main() -> (.status_code: Int32) := {
    if [
        default_host#(.n = 42)() != 42
        or tuple_host#(.n = 41)() != 42
        or allocate_host#(.n = 42)() != 42
    ] { abort }
    if selected_capture#(.n = 42)(.runtime_value = 7) != 42 { abort }
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
