Choice: Type = (..present(.value: Int32), ..empty)

record_width := <.T: Type> () -> (.count: UIntNative) { count = size_of(.type = T) }

read_default := <.T: Type> (.value: T) -> (.result: Int32) {
    #if record_width<.T: T>() > 0 {
        match value.selection {
            ..present selected { result = selected.value }
            ..empty { result = 0 }
        }
    } #else {
        result = 0
    }
}

with_default := <.T: Type, .n: Int32> (.value: T) -> (.result: Int32) {
    result = read_default<
        .T : (
            .item      : T
            .selection : Choice = #run () -> (.result: Choice) {
                if n == 0 { result = ..empty } else { result = ..present(.value = n) }
            }
        )
    >(.value = (.item = value))
}

ArrayChoice: Type = <.n: Int32> (
    ..present(.items: Array<.n = #run () -> (.count: Int32) { count = n }, .t: Int32>)
    ..empty
)

read_empty := <.T: Type> (.value: T) -> (.result: Int32) {
    #if record_width<.T: T>() > 0 {
        match value.selection {
            ..present _ { abort }
            ..empty { result = 42 }
        }
    } #else {
        result = 0
    }
}

with_generic_default := <.n: Int32> () -> (.result: Int32) {
    result = read_empty<
        .T : (
            .selection : ArrayChoice<.n = n> = #run () -> (.choice: ArrayChoice<.n = n>) {
                choice = ..empty
            }
        )
    >(.value = ())
}

main := () -> (.status_code: Int32) {
    if with_default<.T: Int32, .n = 42>(.value = 7) != 42 { abort }
    if with_default<.T: Bool, .n = 41>(.value = true) != 41 { abort }
    if with_default<.T: Int32, .n = 0>(.value = 9) != 0 { abort }
    if [
        [
            #run () -> (.value: Int32) {
                value = with_default<.T: Bool, .n = 42>(.value = true)
            }
        ]
        != 42
    ] { abort }
    if with_generic_default<.n = 1>() != 42 { abort }
    if with_generic_default<.n = 2>() != 42 { abort }
    if [#run () -> (.value: Int32) { value = with_generic_default<.n = 3>() }] != 42 { abort }
    status_code = 42
}
