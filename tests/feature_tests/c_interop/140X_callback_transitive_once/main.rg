Callback() -> (.result: CInt): CFunctionPointer
acquire := once () -> (.result: CInt) { result = 42 }
helper := () -> (.result: CInt) { result = acquire() }
worker := () -> (.result: CInt): CFunction { result = helper() }
main := () -> () { callback ::= Callback(.function = worker) _ = callback }
