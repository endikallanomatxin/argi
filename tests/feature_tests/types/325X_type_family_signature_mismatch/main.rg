Pair := <.Left: Type, .Right: Type> (.left: Left, .right: Right)

accept := <.Family: <.Item: Type> Type> () -> () {}

main := () -> () {
    accept<.Family = Pair>()
}
