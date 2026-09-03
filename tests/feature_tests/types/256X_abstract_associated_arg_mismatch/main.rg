Capability#(.item: Type) : Abstract = ()
Thing : Type = (.value: Int32)

Thing implements Capability#(.item: Int32)

require_uint#(.t: Type: Capability#(.item: UInt32))(.value: &t) -> () := {}

main(.system: System = System()) -> () := {
    thing ::= Thing(.value = 0)
    require_uint(.value = &thing)
}
