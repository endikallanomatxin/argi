Supported<.T: Type>: Contract = ()

Copy<.T: Type>: Contract = (.copy: (.source: T) -> (.result: T))

copy_value := <.T: Type: Supported<T>> (.source: T) -> (.result: T) { result = source }

implement Copy<Int32> (.copy = copy_value)

main := () -> () {}
