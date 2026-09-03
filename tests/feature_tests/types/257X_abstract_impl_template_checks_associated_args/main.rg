Capability#(.item: Type) : Abstract = ()
Other : Abstract = ()

Thing : Type = (.value: Int32)
Thing implements Capability#(.item: Int32)

Wrapper#(.t: Type) : Type = (.marker: Int32)
Wrapper#(.t: Type: Capability#(.item: UInt32)) implements Other

require_other#(.t: Type: Other)(.value: &t) -> () := {}

main(.system: System = System()) -> (.status_code: Int32 = 0) := {
    wrapper ::= Wrapper#(.t: Thing)(.marker = 0)
    require_other(.value = &wrapper)
}
