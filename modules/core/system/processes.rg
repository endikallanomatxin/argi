ProcessCaller : Type = []
-- The capability for calling processes


ProcessHandle : Type = [
   .id: Int64
]


call(pc: $&ProcessCaller&, command: String) : !ProcessHandle {
    ...
}


read(ph: $&ProcessHandle&) : !String {
    ...
}


terminate(ph: $&ProcessHandle&) : ! {
    ...
}


deinit(ph: $&ProcessHadle&) : {
    ph|terminate($&_)
}

