ImplicitlyCopyable#(.Value: Type): Contract = ()

implement ImplicitlyCopyable#(Int8) ()

implement ImplicitlyCopyable#(Int16) ()

implement ImplicitlyCopyable#(Int32) ()

implement ImplicitlyCopyable#(Int64) ()

implement ImplicitlyCopyable#(UIntNative) ()

implement ImplicitlyCopyable#(UInt8) ()

implement ImplicitlyCopyable#(UInt16) ()

implement ImplicitlyCopyable#(UInt32) ()

implement ImplicitlyCopyable#(UInt64) ()

implement ImplicitlyCopyable#(Float16) ()

implement ImplicitlyCopyable#(Float32) ()

implement ImplicitlyCopyable#(Float64) ()

implement ImplicitlyCopyable#(Bool) ()

implement ImplicitlyCopyable#(Void) ()

-- Copying a shared reference preserves its storage dependencies.
implement#(.Value: Type) ImplicitlyCopyable#(&Value) ()
