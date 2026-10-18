Marked#(.T: Type): Contract = ()

Base: Type = (.value: Int32)

Derived: Type = Base

implement Marked#(Base) ()

require_mark#(.T: Type: Marked) := (.value: T) -> () {}

main() -> () := {
    value: Derived = (.value = 1)
    require_mark(.value = value)
}
