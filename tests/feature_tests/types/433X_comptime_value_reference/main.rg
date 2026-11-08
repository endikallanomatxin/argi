Metadata := (.value: &Int32)

Box := #(.metadata: Metadata) (.value: Int32)

main := () -> () {
    n: Int32 = 0
    value ::= Box#(.metadata = (.value = &n))(.value = 0)
}
