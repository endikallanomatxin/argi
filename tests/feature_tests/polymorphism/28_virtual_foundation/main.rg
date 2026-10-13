A: Abstract = (read(.self: &Self) -> (.value: Int32) where {})

Box: Type = (.value: Int32)

Box implements A

read(.self: &Box) -> (.value: Int32) := { value = self&.value }

main() -> (.status_code: Int32) := {
    box :: Box = (.value = 1)
    virtual ::= to_virtual#(.abstract: A)(.value = $&box)
    if virtual.data | convert#(.to: UIntNative)(_) == $&box | convert#(.to: UIntNative)(_) {
        status_code = 0
    }
}
