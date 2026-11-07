AccessCell#(.Provider: Type): Contract = (
    .set: (.self: $&Provider) -> () where { writes(self) }
)
Provider := (.value: $&Int32)
implement AccessCell#(Provider) (
    .set = (.self: $&Provider) -> () { self&.value& = 42 }
)
main := () -> () {
    value :: Int32 = 0
    provider: Provider = (.value = $&value)
    cell ::= Virtual#(AccessCell)($&provider)
    AccessCell#().set(.self = $&cell)
}
