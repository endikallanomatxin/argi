Result : Type = (
    ..ok $&Int32
    ..error Int32
)

read(.pointer: $&Int32) -> (.value: Int32) := {
    value = pointer&
}

main() -> (.status_code: Int32 = 0) := {
    zero :: UIntNative = 0
    result : Result = ..ok cast#(.to: $&Int32)(.value = zero)
    pointer ::= result..ok
    status_code = read(.pointer = pointer).value
}
