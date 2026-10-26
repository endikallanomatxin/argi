foreign := import ("./foreign")
value :: Int32 = 42

read := <.T: Type> (.input: T) -> (.result: Int32) {
    result = value
}

main := () -> (.status_code: Int32) {
    status_code = read(.input = true)
}
