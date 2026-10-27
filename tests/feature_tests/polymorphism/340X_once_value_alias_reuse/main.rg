Args: Type = ()

acquire := once Args -> (.result: Int32) { result = 42 }
alias := acquire

main := () -> () {
    first ::= acquire()
    second ::= alias()
}
