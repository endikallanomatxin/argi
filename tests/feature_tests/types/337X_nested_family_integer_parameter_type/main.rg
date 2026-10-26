Narrow := <.Family: <.count: UInt8> Type> (.flag: Bool)

accept := <.Outer: <.Family: <.count: UIntNative> Type> Type> () -> () {}

main := () -> () {
    accept<.Outer = Narrow>()
}
