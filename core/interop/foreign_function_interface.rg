_ForeignFunctionInterfaceInitArgs: Type = ()

ForeignFunctionInterface: Type = ()

_acquire_foreign_function_interface := once _ForeignFunctionInterfaceInitArgs -> (
    .result : ForeignFunctionInterface
) {
    result = ()
}

ForeignFunctionInterfaceInitArgs: Type = _ForeignFunctionInterfaceInitArgs

implement Init#(ForeignFunctionInterface, ForeignFunctionInterfaceInitArgs) (
    .Result : Type = ForeignFunctionInterface

    .init = _acquire_foreign_function_interface
)
