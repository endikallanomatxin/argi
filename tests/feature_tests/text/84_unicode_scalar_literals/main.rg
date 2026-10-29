identity := #(.T: Type) (.value: T) -> (.result: T) { result = value }

main := () -> () {
    assume error_tracer ::= $&noop_error_tracer
    compiled ::= #run () -> (.result: UInt32) {
        result = scalar_value('🙂')
    }
    if compiled != 128578 { abort }
    ascii :: UnicodeScalar = 'A'
    latin :: UnicodeScalar = 'ñ'
    euro :: UnicodeScalar = '€'
    emoji :: UnicodeScalar = identity(.value = '🙂')
    if scalar_value(ascii) != 65 { abort }
    if scalar_value(latin) != 241 { abort }
    if scalar_value(euro) != 8364 { abort }
    if scalar_value(emoji) != 128578 { abort }
    if scalar_value('\n') != 10 or scalar_value('\0') != 0 { abort }
    values: [3]UnicodeScalar = ('ñ', '€', '🙂')
    if values[0] != latin or values[1] != euro or values[2] != emoji { abort }
    if latin >= euro or emoji <= euro { abort }
    bytes: [4]UInt8 = (0, 0, 0, 0)
    if unwrap_or_abort(.value = utf8_encode(.scalar = emoji, .buffer = view($&bytes))) != 4 {
        abort
    }
    if bytes[0] != 240 or bytes[3] != 130 { abort }
}
