Packet : Type = (.bytes: [2]Int32)
packet() -> (.result: Packet) := { result = (.bytes = (1, 2)) }
main() -> (.status_code: Int32 = 0) := {
    index :: UIntNative = 2
    status_code = packet().bytes[index]
}
