Args := (.value: Bool = true)

Result := (.result: Bool = false)

read := Args -> Result {
    result = value
}

GenericArgs := <.T: Type> (.value: T)

GenericResult := <.T: Type> (.result: T)

identity := <.T: Type> GenericArgs<T> -> GenericResult<T> {
    result = value
}

ForwardArgs := <.T: Type> GenericArgs<T>

forward_identity := <.T: Type> ForwardArgs<T> -> GenericResult<T> {
    result = value
}

read_forwarded := <.T: Type> (.input: &ForwardArgs<T>) -> (.result: T) {
    result = input&.value
}

IdentityType := <.T: Type> T
ReferenceType := <.T: Type> &T
PairType := <.T: Type> [2]T

read_identity := <.T: Type> (.input: IdentityType<T>) -> (.result: T) {
    result = input
}

Provider := (.flag: Bool)

ReachedArgs := <.P: Type> (.provider: &P = reach provider)

read_provider := <.P: Type> ReachedArgs<P> -> Result {
    result = provider&.flag
}

computed ::= #run () -> (.result: Bool) {
    result = forward_identity(.value = identity(.value = read().result).result).result
}

computed_provider ::= #run () -> (.result: Bool) {
    supply ::= Provider(.flag = true)
    assume provider ::= &supply
    result = read_provider().result
}

main() -> () := {
    supply ::= Provider(.flag = true)
    assume provider ::= &supply
    original: GenericArgs<Bool> = (.value = true)
    forwarded: ForwardArgs<Bool> = original
    restored: GenericArgs<Bool> = forwarded
    reference: ReferenceType<Bool> = &restored.value
    pair: PairType<Bool> = (true, false)
    if reference& {} else { abort }
    if pair[0] {} else { abort }
    if pair[1] { abort }
    if restored.value {} else { abort }
    if read_forwarded(.input = &original).result {} else { abort }
    if read_identity(.input = true).result {} else { abort }
    if read_provider().result {} else { abort }
    if computed {} else { abort }
    if computed_provider {} else { abort }
    if read().result {} else { abort }
    if read(.value = false).result { abort }
    if identity<Bool>(.value = true).result {} else { abort }
    if identity(.value = true).result {} else { abort }
    if forward_identity(.value = true).result {} else { abort }
}
