schema ::= import("./schema")

read := schema.Args -> schema.Result {
    result = value
}

defaulted := schema.Args -> schema.Result {}

read_generic := schema.GenericArgs<Bool> -> schema.GenericResult<Bool> {
    result = value
}

computed ::= #run () -> (.result: Bool) {
    result = read().result
}

main() -> () := {
    if read().result {} else { abort }
    if read(.value = false).result { abort }
    if defaulted().result { abort }
    if read_generic(.value = true).result {} else { abort }
    if computed {} else { abort }
}
