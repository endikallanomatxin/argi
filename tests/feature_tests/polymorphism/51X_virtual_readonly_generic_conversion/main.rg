Counter<.Participant: Type>: Contract = (.bump: (.self: $&Participant) -> () where {})

Box := (.value: Int32)

implement Counter<Box> (.bump = _impl_bump_Box)

_impl_bump_Box := (.self: $&Box) -> () { self&.value = self&.value + 1 }

wrap := <.t: Type: Counter> (.value: &t) -> (.result: Virtual<.contract: Counter>) {
    result = to_virtual<.contract: Counter>(.value = value)
}

main := () -> (.status_code: Int32 = 0) {
    box :: Box = (.value = 7)
    handle ::= wrap<.t: Box>(.value = &box).result
    bump(.self = $&handle)
}
