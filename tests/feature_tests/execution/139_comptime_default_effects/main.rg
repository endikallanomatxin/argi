Counter := (.count: Int32 = 0)

next_value := (.counter: $&Counter = reach counter) -> (.value: Int32) {
    counter&.count = counter&.count + 1
    value = counter&.count
}

width := #(.T: Type) () -> (.count: UIntNative) { count = size_of(.type = T) }

read_value := #(.T: Type) (.value: T) -> (.result: Int32) {
    #if width#(.T: T)() > 0 { result = value.extra } #else { result = 0 }
}

make := #(.T: Type) (.item: T, .counter: $&Counter) -> (.result: Int32) {
    assume counter
    result = read_value#(.T: (.item: T, .extra: Int32 = next_value()))(.value = (.item = item))
}

explicit := #(.T: Type) (.item: T, .counter: $&Counter) -> (.result: Int32) {
    assume counter
    result = read_value#(.T: (.item: T, .extra: Int32 = next_value()))(
        .value = (.item = item, .extra = 42)
    )
}

exercise := () -> (.result: Int32) {
    counter :: Counter = Counter()
    if make(.item = 7, .counter = $&counter) != 1 { abort }
    if make(.item = 8, .counter = $&counter) != 2 { abort }
    if explicit(.item = 9, .counter = $&counter) != 42 { abort }
    if counter.count != 2 { abort }
    other :: Counter = (.count = 10)
    if make(.item = 10, .counter = $&other) != 11 { abort }
    if counter.count != 2 or other.count != 11 { abort }
    result = 42
}

main := () -> (.status_code: Int32) {
    if [#run () -> (.value: Int32) { value = exercise() }] != 42 { abort }
    status_code = exercise()
}
