dep := import ("./dep")

Product<.Left: Type, .Right: Type>: Contract = (
    .Result : Type

    .multiply : (.left: Left, .right: Right) -> (.value: Result) where {}
)

implement Product<dep.Row, dep.Column> (.Result: Type = Int32)

main := () -> () {}
