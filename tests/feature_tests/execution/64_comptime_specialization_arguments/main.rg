compute() -> (.result: Int32 = 0) := {
    while result < 2 { result = result + 1 }
}

DefaultHolder#(.n: Int32 = #run () -> (.value: Int32) { value = compute() }): Type = (
    .items : Array#(.n = n, .t: Int32)
)

Holder#(.n: Int32): Type = (.items: Array#(.n = n, .t: Int32))

increment(.value: Int32) -> (.result: Int32 = value + 1) := {}

result#(.n: Int32)() -> (.value: Int32 = n) := {}

derive#(.n: Int32)() -> (.value: Int32) := {
    value = result#(.n = #run () -> (.result: Int32) { result = increment(.value = n) })()
}

main() -> (.status_code: Int32 = 0) := {
    data :: Holder#(.n = #run () -> (.value: Int32) { value = compute() }) = (
        .items = (20, 42)
    )
    if data.items[1] != 42 { abort }
    direct :: Array#(.n = #run () -> (.value: Int32) { value = compute() }, .t: Int32) = (
        20,
        42
    )
    if direct[1] != 42 { abort }
    defaulted :: DefaultHolder#() = (.items = (20, 42))
    if defaulted.items[1] != 42 { abort }
    if derive#(.n = 3)() != 4 { abort }
    status_code = derive#(.n = 41)()
}
