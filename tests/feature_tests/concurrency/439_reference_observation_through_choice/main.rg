View := (.data: &UInt8)
offset := (.self: &View, .index: UIntNative) -> (.result: Errable#(&UInt8, (..out_of_bounds))) {
    if index >= 2 {
        result = ..error(.reason = ..out_of_bounds)
        return
    }
    result = ..ok trusted_reference_offset#(UInt8)(.base = self&.data, .elements = index).reference
}
read := (.self: &View, .index: UIntNative) -> (.result: Errable#(UInt8, (..out_of_bounds))) {
    byte ::= offset(.self = self, .index = index)!
    result = ..ok byte&
}
main := (.system: System) -> () {
    cell ::= unwrap_or_abort(AtomicUInt32(.ffi = system.ffi, .initial = 0))
    shared ::= $$&cell
    bytes : [2]UInt8 = (7, 8)
    view ::= View(.data = &bytes[0])
    if unwrap_or_abort(read(.self = &view, .index = 1)) != 8 { abort }
    if shared_load(.self = shared) != 0 { abort }
    recover_ordinary(.owner = $&cell)
}
