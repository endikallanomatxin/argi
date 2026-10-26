make_generic := <.T: Type> () -> (.value: T) { value = zeroed<.t: T>() }

identity := <.T: Type> (.value: T = make_generic()) -> (.result: T) { result = value }

main := () -> () {
    cached ::= make_generic<.T: Int32>()
    missing ::= identity()
}
