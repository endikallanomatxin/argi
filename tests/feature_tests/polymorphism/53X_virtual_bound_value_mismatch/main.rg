Fixed#(.Participant: Type): Contract = (.n: Int)

Box: Type = (.value: Int32)

implement Fixed#(Box) (.n: Int = 1)

main() -> () := {
    box :: Box = (.value = 7)
    handle ::= to_virtual#(.contract: Fixed#(.n = 2))(.value = &box)
}
