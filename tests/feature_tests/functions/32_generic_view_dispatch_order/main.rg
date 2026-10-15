require_mutable(.value: ArrayView#(.t: Float64)) -> () := {}
forward#(.n: UIntNative)(.array: $&Array#(.n = n, .t: Float64)) -> () := {
    require_mutable(.value = view(.array = array))
}
main() -> (.status_code: Int32 = 0) := {
    first: [4]Float64 = (1.0, 2.0, 3.0, 4.0)
    readonly ::= view(.array = &first)
    second :: [4]Float64 = (5.0, 6.0, 7.0, 8.0)
    require_mutable(.value = view(.array = $&second))
    forward(.array = $&second)
    if length(.self = &readonly).count != 4 { abort }
}
