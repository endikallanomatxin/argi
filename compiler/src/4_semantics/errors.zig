pub const SemErr = error{
    SymbolAlreadyDefined,
    SymbolNotFound,
    ConstantReassignment,
    InvalidType,
    UnknownType,
    AbstractNeedsDefault,
    MissingReturnValue,
    NotYetImplemented,
    OutOfMemory,
    OptionalUnwrap,
    AmbiguousOverload,
    Reported,
};
