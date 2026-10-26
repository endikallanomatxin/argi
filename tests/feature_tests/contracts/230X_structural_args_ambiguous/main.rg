Inspect<.Args: Type>: Contract = (.inspect: (.args: Args) -> ())

implement<.T: Type> Inspect<(.left: Int32, .right: T)> (
    .inspect = (.args: (.left: Int32, .right: T)) -> () {}
)

implement<.T: Type> Inspect<(.left: T, .right: UInt8)> (
    .inspect = (.args: (.left: T, .right: UInt8)) -> () {}
)

main := () -> () {
    args :: (.left: Int32, .right: UInt8) = (.left = 1, .right = 2)
    Inspect<(.left: Int32, .right: UInt8)>.inspect(args)
}
