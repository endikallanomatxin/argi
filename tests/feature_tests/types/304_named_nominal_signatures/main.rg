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

computed ::= #run () -> (.result: Bool) {
    result = identity<Bool>(.value = read().result).result
}

main() -> () := {
    if computed {} else { abort }
    if read().result {} else { abort }
    if read(.value = false).result { abort }
    if identity<Bool>(.value = true).result {} else { abort }
}
