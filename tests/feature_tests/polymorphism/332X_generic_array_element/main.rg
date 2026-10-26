invalid := <.T: Type> (.marker: T) -> () {
    bytes: [1]UInt8 = (256)
}

main := () -> () { invalid<Int32>(1) }
