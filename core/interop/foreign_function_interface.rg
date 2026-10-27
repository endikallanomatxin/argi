_ForeignFunctionInterfaceInitArgs: Type = ()

ForeignFunctionInterface: Type = ()

_acquire_foreign_function_interface := once _ForeignFunctionInterfaceInitArgs -> (
    .result : ForeignFunctionInterface
) {
    result = ()
}

implement Init#(ForeignFunctionInterface) (
    .init = _acquire_foreign_function_interface
)
