Sink: Type = (
    .flush_calls : UIntNative = 0
    .fail_flush  : Bool       = false
    .fail_write  : Bool       = false
)

finish(
        .sink  : $&Sink,
        .early : Bool
    ) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed)) = ..ok Void()
    ) := {
    assume writer := sink
    #defer {
        Writer#().flush(writer) handle error { result = ..error ~error }
    }

    Writer#().write_byte(writer, 65) handle error {
        result = ..error ~error
        return
    }
    if early { return }
    Writer#().write_byte(writer, 66) handle error {
        result = ..error ~error
        return
    }
}

run_main() -> !Void = ..ok Void() := {
    normal ::= Sink()
    finish($&normal, false)!
    if normal.flush_calls != 1 { abort }

    early ::= Sink()
    finish($&early, true)!
    if early.flush_calls != 1 { abort }

    failed ::= Sink(.fail_flush = true)
    match finish($&failed, true) {
        ..ok _ { abort }
        ..error error { if error.reason != ..stream_flush_failed { abort } }
    }
    if failed.flush_calls != 1 { abort }

    write_failed ::= Sink(.fail_write = true)
    match finish($&write_failed, false) {
        ..ok _ { abort }
        ..error error { if error.reason != ..stream_write_failed { abort } }
    }
    if write_failed.flush_calls != 1 { abort }

    both_failed ::= Sink(.fail_flush = true, .fail_write = true)
    match finish($&both_failed, false) {
        ..ok _ { abort }
        ..error error { if error.reason != ..stream_flush_failed { abort } }
    }
    if both_failed.flush_calls != 1 { abort }

}

main#(.WriterType: Type: Writer#(WriterType))(.writer: $&WriterType = reach writer) -> (.status_code: Int32 = 1) := {
    run_main()!!!
    status_code = 0
}

implement Writer#(Sink)(
    .write_byte = (
            .self : $&Sink,
            .byte : UInt8
        ) -> (
            .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
        ) {
        if self&.fail_write {
            result = ..error(.reason = ..stream_write_failed)
            return
        }
        result = ..ok Void()
    }

    .flush = (
            .self : $&Sink
        ) -> (
            .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
        ) {
        self&.flush_calls = self&.flush_calls + 1
        if self&.fail_flush {
            result = ..error(.reason = ..stream_flush_failed)
            return
        }
        result = ..ok Void()
    }
)
