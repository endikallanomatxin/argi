Open#(.T: Type): Contract = (.read: _)

Owner := (.value: Int32)

implement Open#(Owner) (
    .read = (.self: &Owner) -> (.result: Int32) { result = self&.value }
)

main := () -> () {
    owner: Owner = (.value = 42)
    handle ::= to_virtual#(.contract: Open)(.value = &owner)
}
