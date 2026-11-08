Config := (.name: StringView, .enabled: Bool, .fallback: ?UInt8)

Value := #(.T: Type, .config: Config) (.value: T)

read_config := #(.T: Type, .config: Config) (.value: &Value#(T, config)) -> (.name: StringView) {
    if config.enabled == false { abort }
    match config.fallback { ..none { abort } ..some entry { if entry.value != 7 { abort } } }
    name = config.name
}

same := #(.T: Type) (.left: &T, .right: &T) -> () {}

Named := #(.name: StringView = "default") (.label: StringView = name)

evaluate := #(.name: StringView) () -> (.ok: Bool) {
    value ::= Named#(name)()
    ok = value.label == name
}

ArrayMetadata := #(.values: [2]UInt8) (.value: Int32)
array_sum := #(.values: [2]UInt8) (.self: &ArrayMetadata#(values)) -> (.sum: UInt8) {
    sum = values[0] + values[1]
}

gated := #(.enabled: Bool) () -> (.value: Int32) {
    #if enabled { value = 1 } else { value = 2 }
}

Count := UIntNative
infer_count := #(.n: Count) (.values: [n]UInt8) -> (.count: UIntNative) { count = n }
Configured := #(.default_value: ?UInt8) (.value: UInt8)
forward_count := #(.n: UInt8) () -> (.result: UInt8) {
    configured ::= Configured#(.default_value = ..some(.value = n))(.value = n)
    result = configured.value
}

main := () -> (.status_code: Int32 = 0) {
    value ::= Value#(
        UInt8, .config = (.name = "sample", .enabled = true, .fallback = ..some(.value = 7))
    )(.value = 42)
    reordered ::= Value#(
        UInt8, .config = (.fallback = ..some(.value = 7), .enabled = true, .name = "sample")
    )(.value = 9)
    same(&value, &reordered)
    array ::= ArrayMetadata#(.values = (3, 4))(.value = 0)
    if array_sum(&array) != 7 { abort }
    if gated#(.enabled = true)() != 1 or gated#(.enabled = false)() != 2 { abort }
    numbers: [2]UInt8 = (3, 4)
    if infer_count(numbers) != 2 or forward_count#(.n = 7)() != 7 { abort }
    named ::= Named#("named")()
    if named.label != "named" { abort }
    #if evaluate#("compiled")() == false { abort }
    if read_config(&value) != "sample" { abort }
    if [
        size_of(
            .type = Value#(
                UInt8,
                .config = (.name = "sample", .enabled = true, .fallback = ..some(.value = 7))
            )
        )
        != size_of(.type = UInt8)
    ] { abort }
}
