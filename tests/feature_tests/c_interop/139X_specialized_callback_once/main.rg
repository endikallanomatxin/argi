Callback(.value: CInt) -> (.result: CInt): CFunctionPointer
worker := once #(.T: Type) (.value: T) -> (.result: T): CFunction { result = value }
main := () -> () {
    callback ::= Callback(.function = worker#(CInt))
    _ = callback
}
