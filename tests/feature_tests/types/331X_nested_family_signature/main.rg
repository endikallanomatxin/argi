Outer := <.Nested: <.Left: Type, .Right: Type> Type> (.flag: Bool)

accept := <.Family: <.Nested: <.Item: Type> Type> Type> () -> () {}

main := () -> () {
    accept<.Family = Outer>()
}
