Capability<.Participant: Type>: Contract = (.item: Type)
Thing : Type = ()

implement Capability<Thing> (.item: Type = Int32)
implement Capability<Thing> (.item: Type = UInt32)

main := (.system: System) -> ()  {}
