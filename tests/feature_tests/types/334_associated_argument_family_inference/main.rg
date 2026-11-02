Owner := (.value: Int32)

Provider := (.flag: Bool)

OtherProvider := (.marker: UInt8)

Arguments := #(.P: Type) (.value: Int32, .provider: &P)

Construct#(.Target: Type): Contract = (
    .Args  : #(.P: Type) Type
    .build : #(.P: Type) Args#(P) -> (.result: Target)
)

implement Construct#(Owner) (
    .Args  : #(.P: Type) Type = Arguments
    .build = #(.P: Type) Arguments#(P) -> (.result: Owner) { result = (.value = value) }
)

forward := #(.P: Type) (.provider: &P) -> (.result: Owner) {
    assume provider
    result = Construct#(Owner).build(.value = 42)
}

evaluate := () -> (.result: Int32) {
    source: Provider = (.flag = true)
    assume provider ::= &source
    first ::= Construct#(Owner).build(.value = 42, .provider = &source)
    second ::= Construct#(Owner).build(.value = 42)
    third ::= forward(.provider = &source)
    alternative: OtherProvider = (.marker = 1)
    fourth ::= Construct#(Owner).build(.value = 42, .provider = &alternative)
    fifth ::= forward(.provider = &alternative)
    if fourth.value != first.value or fifth.value != first.value { abort }
    if first.value != second.value or first.value != third.value { abort }
    result = first.value
}

known ::= #run () -> (.result: Int32) { result = evaluate() }

main := () -> (.status_code: Int32) {
    if known != 42 { abort }
    status_code = evaluate()
}
