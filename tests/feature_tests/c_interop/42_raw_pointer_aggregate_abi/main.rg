Pointers : CStruct = (.values: [2]RawPointer#(.t: UInt8))
Element : CStruct = (.data: RawPointer#(.t: UInt8), .count: CSize)
Elements : CStruct = (.values: [2]Element)
Address : CUnion = (.pointer: RawPointer#(.t: UInt8), .integer: CSize)
Alternatives : CUnion = (.pointers: [2]RawPointer#(.t: UInt8), .numbers: [2]CDouble)
Pointers implements ImplicitlyCopyable
Element implements ImplicitlyCopyable
Elements implements ImplicitlyCopyable
Address implements ImplicitlyCopyable
Alternatives implements ImplicitlyCopyable
_get() -> (.result: Pointers) : CFunction(.symbol = "argi_c_pointers_get")
_elements() -> (.result: Elements) : CFunction(.symbol = "argi_c_elements_get")
_address() -> (.result: Address) : CFunction(.symbol = "argi_c_address_get")
_alternatives() -> (.result: Alternatives) : CFunction(.symbol = "argi_c_alternatives_get")
_echo(.value: Pointers) -> (.result: Pointers) : CFunction(.symbol = "argi_c_pointers_echo")
_crowded(.a: CInt, .b: CInt, .c: CInt, .d: CInt, .e: CInt, .value: Pointers, .last: CInt) -> (.result: Pointers) : CFunction(.symbol = "argi_c_pointers_crowded")
_probe() -> (.result: CInt) : CFunction(.symbol = "argi_c_aggregate_probe")
_forward(.index: UIntNative) -> (.result: RawPointer#(.t: UInt8)) := {
    values := _get()
    result = values.values[index]
}
_forward_element(.index: UIntNative) -> (.result: Element) := {
    values := _elements()
    result = values.values[index]
}
argi_c_pointers_export(.value: Pointers) -> (.result: Pointers) : CFunction(.export = true) := { result = value }
argi_c_elements_export(.value: Elements) -> (.result: Elements) : CFunction(.export = true) := { result = value }
argi_c_address_export(.value: Address) -> (.result: Address) : CFunction(.export = true) := { result = value }
argi_c_alternatives_export(.value: Alternatives) -> (.result: Alternatives) : CFunction(.export = true) := { result = value }
main(.system: System) -> (.status_code: Int32 = 0) := {
    assume ffi := system.ffi
    pointers := _get()
    first := pointers.values[0].address
    if first == 0 or pointers.values[1].address != 0 { status_code = 1 }
    if _forward(0).address != first or _forward(1).address != 0 { status_code = 2 }
    element := _forward_element(0)
    if element.data.address != first or element.count != 3 { status_code = 3 }
    if _forward_element(1).data.address != 0 { status_code = 4 }
    if _address().pointer.address != first { status_code = 5 }
    alternatives := _alternatives()
    if alternatives.pointers[0].address != first or alternatives.pointers[1].address != 0 { status_code = 6 }
    echoed := _echo(pointers)
    if echoed.values[0].address != first or echoed.values[1].address != 0 { status_code = 7 }
    crowded := _crowded(1, 2, 3, 4, 5, pointers, 6)
    if crowded.values[0].address != first { status_code = 8 }
    if _probe() != 0 { status_code = 9 }
}
