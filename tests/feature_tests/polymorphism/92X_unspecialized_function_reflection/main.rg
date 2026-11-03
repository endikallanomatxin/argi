identity := #(.T: Type) (.value: T) -> (.result: T) { result = value }
main := () -> () {
    args: inputs_of#(identity) = (.value = 42)
    _ = args
}
