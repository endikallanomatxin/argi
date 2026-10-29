-- Private IEEE representation operations are scoped to their value participant.
_FloatRepresentation#(.Value: Type): Contract = (
    .encoding     : (.value: Value) -> (.encoding: _FloatEncoding)
    .replace_bits : (.value: Value, .bits: UInt64) -> (.result: Value)
)

implement _FloatRepresentation#(Float16) (
    .encoding = (.value: Float16) -> (.encoding: _FloatEncoding) {
        assume error_tracer ::= [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
        bits ::= trusted_reinterpret_reference#(.from: Float16, .to: UInt16)(
            .base = &value
        ).reference&
        encoding = (
            .bits           = bits | convert#(.to: UInt64)(_)
            .fraction_unit  = 1024
            .exponent_limit = 32
            .bias           = 15
        )
    }

    .replace_bits = (.value: Float16, .bits: UInt64) -> (.result: Float16) {
        assume error_tracer ::= [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
        native ::= unwrap_or_abort(.value = bits | convert#(.to: UInt16)(_))

        result = trusted_reinterpret_reference#(.from: UInt16, .to: Float16)(
            .base = &native
        ).reference&
    }
)

implement _FloatRepresentation#(Float32) (
    .encoding = (.value: Float32) -> (.encoding: _FloatEncoding) {
        assume error_tracer ::= [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
        bits ::= trusted_reinterpret_reference#(.from: Float32, .to: UInt32)(
            .base = &value
        ).reference&
        encoding = (
            .bits           = bits | convert#(.to: UInt64)(_)
            .fraction_unit  = 8388608
            .exponent_limit = 256
            .bias           = 127
        )
    }

    .replace_bits = (.value: Float32, .bits: UInt64) -> (.result: Float32) {
        assume error_tracer ::= [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
        native ::= unwrap_or_abort(.value = bits | convert#(.to: UInt32)(_))

        result = trusted_reinterpret_reference#(.from: UInt32, .to: Float32)(
            .base = &native
        ).reference&
    }
)

implement _FloatRepresentation#(Float64) (
    .encoding = (.value: Float64) -> (.encoding: _FloatEncoding) {
        bits ::= trusted_reinterpret_reference#(.from: Float64, .to: UInt64)(
            .base = &value
        ).reference&
        encoding = (
            .bits           = bits
            .fraction_unit  = 4503599627370496
            .exponent_limit = 2048
            .bias           = 1023
        )
    }

    .replace_bits = (.value: Float64, .bits: UInt64) -> (.result: Float64) {
        result = trusted_reinterpret_reference#(.from: UInt64, .to: Float64)(
            .base = &bits
        ).reference&
    }
)
