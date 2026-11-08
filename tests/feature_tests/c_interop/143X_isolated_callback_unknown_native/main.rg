Callback(.context: $&ForeignFunctionInterface) -> (.result: CInt): CFunctionPointer(.isolated = true)
_absolute(.value: CInt) -> (.result: CInt): CFunction(.symbol = "abs")
read := (.context: $&ForeignFunctionInterface) -> (.result: CInt): CFunction {
    result = _absolute(.value = -7, .ffi = context)
}
worker := (.context: $&ForeignFunctionInterface) -> (.result: CInt): CFunction {
    result = read(.context = context)
}
main := () -> () {
    callback ::= Callback(.function = worker)
    _ = callback
}
