Callback(.value: CInt) -> (.result: CInt): CFunctionPointer
compute := (.value: CInt) -> (.result: CInt) { result = value }
worker := #(.F: Function) (.value: CInt) -> (.result: CInt): CFunction { result = F(.value = value) }
main := () -> () {
    callback ::= Callback(.function = worker#(compute))
    _ = callback(.value = 1)
}
