-- Observing an address carries no safe-reference or acquisition evidence.
implement#(.T: Type) Convert#(&T, UIntNative) (
        .Result  : Type = UIntNative
        .convert = (
                .value : &T
            ) -> (
                .result : Result
            ) {
            result = __reference_address(.value = value)
        }
    )

implement#(.T: Type) Convert#($&T, UIntNative) (
        .Result  : Type = UIntNative
        .convert = (
                .value : $&T
            ) -> (
                .result : Result
            ) {
            result = __reference_address(.value = value)
        }
    )
