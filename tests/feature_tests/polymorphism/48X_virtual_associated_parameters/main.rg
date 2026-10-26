A<.Participant: Type>: Contract = (.item: Type)

Box := (.value: Int32)

implement A<Box> (.item: Type = Int32)

main := () -> (.status_code: Int32 = 0) {
    box :: Box = (.value = 7)
    handle ::= to_virtual<.contract: A<.item: Float32>>(.value = $&box)
}
