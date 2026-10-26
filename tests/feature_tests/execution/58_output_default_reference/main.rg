reference := <.T: Type> (.target: &T) -> (.result: &T = target) {}

main := () -> (.status_code: Int32 = 0) {
    value :: Int32 = 42
    result := reference<.T: Int32>(.target = &value)
    status_code = result&
}
