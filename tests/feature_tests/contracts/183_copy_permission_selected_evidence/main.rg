Packet: Type = (.value: Int32)
implement ImplicitlyCopyable#(Packet) ()
Box#(.T: Type): Type = (.value: T)
implement#(.T: Type: ImplicitlyCopyable) ImplicitlyCopyable#(Box#(T)) ()
main := () -> (.status_code: Int32 = 0) {
    original ::= Box#(Packet)(.value = Packet(.value = 42))
    duplicate ::= original
    explicit ::= InfalliblyCopyable#(Box#(Packet)).copy(&original).value
    if duplicate.value.value != explicit.value.value { abort }
}
