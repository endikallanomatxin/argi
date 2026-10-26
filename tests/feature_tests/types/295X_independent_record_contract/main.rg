Marked<.T: Type>: Contract = ()

Base := (.value: Int32)

Derived := (.value: Int32)

implement Marked<Base> ()

require_mark := <.T: Type: Marked> (.value: T) -> () {}

main := () -> () {
    value: Derived = (.value = 1)
    require_mark(.value = value)
}
