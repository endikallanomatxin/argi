api := import ("./api")

implement<.T: Type> api.Inspect<&api.Box<T>> (
    .inspect = (.value: &api.Box<T>) -> (.result: Int32) { result = 0 }
)

main := () -> () {}
