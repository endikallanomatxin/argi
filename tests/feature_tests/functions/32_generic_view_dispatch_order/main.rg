require_mutable(.value: MutableArrayView#(.t: Float64)) -> () := {}

forward#(.n: UIntNative)(.array: $&Array#(.n = n, .t: Float64)) -> () := {
    require_mutable(.value = view(.self = array))
}

main() -> (.status_code: Int32 = 0) := {
    first: [4]Float64 = (1.0, 2.0, 3.0, 4.0)
    readonly ::= view(.self = &first)
    second :: [4]Float64 = (5.0, 6.0, 7.0, 8.0)
    require_mutable(.value = view(.self = $&second))
    forward(.array = $&second)
    if length(.self = &readonly).count != 4 { abort }
}
