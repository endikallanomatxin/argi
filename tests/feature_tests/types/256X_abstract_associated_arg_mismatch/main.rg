Capability#(.Participant: Type): Contract = (.item: Type)
Thing := (.value: Int32)

implement Capability#(Thing) (.item: Type = Int32)

require_uint := #(.t: Type: Capability#(.item: UInt32)) (.value: &t) -> ()  {}

main := (.system: System) -> ()  {
    thing ::= Thing(.value = 0)
    require_uint(.value = &thing)
}
