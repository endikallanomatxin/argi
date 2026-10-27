First<.Value: Type>: Contract = ()

Second<.Value: Type>: Contract = ()

Restricted := <.Item: Type: Second<Item>> (.value: Item)

accept := <.Family: <.T: Type: First<T>> Type> () -> () {}

main := () -> () { accept<.Family = Restricted>() }
