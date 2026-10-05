Sink: Type = (
    .flush_calls : UIntNative = 0
    .fail_flush  : Bool       = false
    .fail_write  : Bool       = false
)

Sink implements Writer

write_byte(
        .self : $&Sink,
        .byte : UInt8
    ) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) := {
    if self&.fail_write {
        result = ..error(.reason = ..stream_write_failed)
        return
    }
    result = ..ok Void()
}

flush(
        .self : $&Sink
    ) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) := {
    self&.flush_calls = self&.flush_calls + 1
    if self&.fail_flush {
        result = ..error(.reason = ..stream_flush_failed)
        return
    }
    result = ..ok Void()
}

finish(.sink: $&Sink, .early: Bool) -> !Void = ..ok Void() := {
    assume writer := sink
    #defer flush(writer)!

    write_byte(writer, 65)!
    if early { return }
    write_byte(writer, 66)!
}

main() -> !Void = ..ok Void() := {
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
