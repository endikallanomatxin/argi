Mode: Type = (..quiet, ..verbose)

Options := #(.T: Type) (.value: T, .mode: Mode, .enabled: Bool, .marker: UnicodeScalar)

OptionsInitArgs: Type = #(.T: Type) (
    .value   : T,
    .mode    : Mode          = ..quiet,
    .enabled : Bool          = true,
    .marker  : UnicodeScalar = 'Q'
)

implement#(.T: Type) Init#(Options#(T), OptionsInitArgs#(T)) (
    .Result : Type = Options#(T)

    .init = OptionsInitArgs#(T) -> (.result: Result) {
        result = (.value = value, .mode = mode, .enabled = enabled, .marker = marker)
    }
)

main := () -> (.status_code: Int32 = 0) {
    defaults ::= Options#(Int32)(.value = 42)
    if defaults.value != 42 or defaults.enabled == false or defaults.marker != 'Q' { abort }
    if is(.value = defaults.mode, .variant = ..quiet) {} else { abort }
    explicit ::= Options#(Int32)(.value = 7, .mode = ..verbose, .enabled = false, .marker = 'V')
    if explicit.value != 7 or explicit.enabled or explicit.marker != 'V' { abort }
    if is(.value = explicit.mode, .variant = ..verbose) {} else { abort }
}
