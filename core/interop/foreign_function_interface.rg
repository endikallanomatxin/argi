ForeignFunctionInterface: Type = ()

once _acquire_foreign_function_interface := (.args: ()) -> (.result: ForeignFunctionInterface) {
    result = ()
}

implement Init#(ForeignFunctionInterface, ()) (
    .Result: Type = ForeignFunctionInterface
    .init = _acquire_foreign_function_interface
)
