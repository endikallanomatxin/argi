Capability<.Participant: Type>: Contract = (.item: Type)
Other<.Participant: Type>: Contract = ()

Thing := (.value: Int32)
implement Capability<Thing> (.item: Type = Int32)

Wrapper := <.t: Type> (.marker: Int32)
implement<.t: Type: Capability<.item: UInt32>> Other<Wrapper<.t: t>> ()

require_other := <.t: Type: Other> (.value: &t) -> ()  {}

main := (.system: System) -> (.status_code: Int32 = 0)  {
    wrapper ::= Wrapper<.t: Thing>(.marker = 0)
    require_other(.value = &wrapper)
}
