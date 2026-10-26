Narrow := <.count: UInt8> (.flag: Bool)

accept := <.Family: <.count: UIntNative> Type> () -> () {}

main := () -> () {
    accept<.Family = Narrow>()
}
