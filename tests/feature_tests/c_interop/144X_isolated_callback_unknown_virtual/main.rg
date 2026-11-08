Callback() -> (.result: CInt): CFunctionPointer(.isolated = true)
Reader#(.Provider: Type): Contract = (
    .get: (.self: &Provider) -> (.result: CInt) where {}
)
implement Reader#(CInt) (
    .get = (.self: &CInt) -> (.result: CInt) { result = self& }
)
read := () -> (.result: CInt) {
    value: CInt = 7
    reader ::= Virtual#(Reader)(&value)
    result = Reader#().get(&reader)
}
worker := () -> (.result: CInt): CFunction { result = read() }
main := () -> () {
    callback ::= Callback(.function = worker)
    _ = callback
}
