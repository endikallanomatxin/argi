Shape : Abstract = ()

Box : Type = (
    .value: Int32
)

Box implements Shape

main() -> (.status_code: Int32) := {
    box :: Box = (.value = 42)
    erased : Virtual#(.abstract: Shape) = to_virtual#(.abstract: Shape)(.value = $&box)
    original ::= cast#(.to: UIntNative)(.value = $&box)
    erased_data ::= cast#(.to: UIntNative)(.value = erased.data)
    if original == erased_data {
        status_code = 0
    } else {
        status_code = 1
    }
}
