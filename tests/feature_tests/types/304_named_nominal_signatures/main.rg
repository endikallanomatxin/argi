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

ForwardArgs: Type = <.T: Type> GenericArgs<T>

forward_identity := <.T: Type> ForwardArgs<T> -> GenericResult<T> {
    result = value
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
    if read_provider().result {} else { abort }
    if computed {} else { abort }
    if computed_provider {} else { abort }
    if read().result {} else { abort }
    if read(.value = false).result { abort }
    if identity<Bool>(.value = true).result {} else { abort }
    if identity(.value = true).result {} else { abort }
    if forward_identity(.value = true).result {} else { abort }
}
