_ForeignFunctionInterfaceInitArgs: Type = ()

ForeignFunctionInterface: Type = ()

once _acquire_foreign_function_interface := (.args: _ForeignFunctionInterfaceInitArgs) -> (
    .result : ForeignFunctionInterface
) {
    result = ()
}

implement Init#(ForeignFunctionInterface, _ForeignFunctionInterfaceInitArgs) (
    .Result : Type = ForeignFunctionInterface
    .init   = _acquire_foreign_function_interface
)
