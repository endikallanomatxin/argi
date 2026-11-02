compute := () -> (.value: Int32 = 42) {}

result := #(.n: Int32) () -> (.value: Int32 = n) {}

defaulted := #(.T: Type) (
    .ignored : T,
    .value   : Int32 = result#(.n = #run () -> (.value: Int32) { value = compute() })()
    .tail    : Int32 = 0
) -> (.output: Int32 = [value + tail]) {}

ordinary := #(.T: Type) (.ignored: T, .value: Int32 = result#(.n = 42)()) -> (
    .output : Int32 = value
) {}

main := () -> (.status_code: Int32 = 0) {
    if ordinary#(.T: Int32)(.ignored = 0) != 42 { abort }
    status_code = defaulted(.ignored = 0)
}
