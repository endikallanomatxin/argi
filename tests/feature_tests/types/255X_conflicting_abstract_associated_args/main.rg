Capability#(.item: Type) : Abstract = ()
Thing : Type = ()

Thing implements Capability#(.item: Int32)
Thing implements Capability#(.item: UInt32)

main(.system: System = System()) -> () := {}
