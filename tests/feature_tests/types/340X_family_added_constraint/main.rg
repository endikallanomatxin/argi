Restricted := <.T: Type: ImplicitlyCopyable<T>> (.value: T)

accept := <.Family: <.T: Type> Type> () -> () {}

main := () -> () { accept<.Family = Restricted>() }
