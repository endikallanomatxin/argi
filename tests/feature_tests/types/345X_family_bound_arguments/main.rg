Related<.Left: Type, .Right: Type>: Contract = ()

Restricted := <.Item: Type: Related<Item, Bool>> (.value: Item)

accept := <.Family: <.T: Type: Related<T, Int32>> Type> () -> () {}

main := () -> () { accept<.Family = Restricted>() }
