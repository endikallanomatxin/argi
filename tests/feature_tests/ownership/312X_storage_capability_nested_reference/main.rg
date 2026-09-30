consume(.address: UIntNative, .root: &Any) -> (.raw: RawPointer#(.t: UInt8)) := { raw = establish_inherited_storage(.address = address, .root = root).raw }
Holder : Type = (.address: &UIntNative)
from_holder(.holder: &Holder, .root: &Any) -> () := { raw ::= consume(.address = holder&.address&, .root = root).raw }
main(.system: System) -> (.status_code: Int32 = 0) := {
    marker :: UInt8 = 0
    root ::= erase_reference#(.t: UInt8)(.base = &marker).reference
    address ::= malloc(.size = 8, .ffi = system.ffi).address
    holder :: Holder = (.address = &address)
    from_holder(.holder = &holder, .root = root)
    raw ::= consume(.address = address, .root = root).raw
}
