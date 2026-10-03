# Duration and clocks

Time values are ordinary implicitly copyable values. Reading a clock or
blocking the current thread requires the `Clock` capability. These operations
need no allocator and do not grant access to unrelated system resources.

## Duration

`Duration(.nanoseconds: UInt64)` returns a `Duration` directly. Its private
representation is an unsigned nanosecond count, including zero and extending
through the full `UInt64` range. Durations never represent negative intervals.

The `.microseconds`, `.milliseconds`, and `.seconds` constructors return
`Errable<Duration, out_of_range>` because scaling to nanoseconds may overflow.
The accessors `nanoseconds`, `microseconds`, `milliseconds`, and `seconds`
receive `.self: &Duration` and return `.value: UInt64`; coarser units discard
the fractional part.

`add(.left: Duration, .right: Duration)` and `subtract` return
`Errable<Duration, out_of_range>`. Addition rejects overflow and subtraction
rejects a negative result. Neither operation wraps or saturates. Equality
uses `==` or `!=`; `compare(.left, .right).order` is -1, 0, or 1.

## Clock domains

`MonotonicInstant` has an unspecified native origin. Its private nanosecond
count cannot be constructed from a civil timestamp. Use
`elapsed(.start: MonotonicInstant, .end: MonotonicInstant)` to obtain
`Errable<Duration, out_of_range>`; an end preceding the start is rejected.
Repeated identical readings yield a zero duration. Readings in the same native
clock domain can be compared with `==`, `!=`, and `compare`.

`UnixTimestamp` represents civil time as signed seconds from the Unix epoch
plus a nonnegative nanosecond fraction below 1,000,000,000. For example, one
nanosecond before the epoch is seconds -1 and fraction 999,999,999.
`UnixTimestamp(.seconds: Int64)` returns a value directly with zero fraction;
the additional `.nanoseconds: UInt32` input returns
`Errable<UnixTimestamp, out_of_range>` and rejects an unnormalized fraction.
The fields are private. `unix_seconds(.self: &UnixTimestamp).value` returns
`Int64`, and `nanoseconds(.self).value` returns `UInt32`. Equality and `compare`
use chronological order, comparing seconds before the fractional component.

Civil time can jump in either direction when the system clock changes.
Monotonic readings do not follow those adjustments. Whether time spent in
system suspension is included depends on the platform. Nanosecond units do
not promise nanosecond clock resolution. Instants belong to their native clock
domain and are not a persistent or cross-machine timestamp format.

## Capability operations

The entry scope creates `Clock` and lends it through `System.clock`. A clock
retains its foreign-call dependency; constructing one requires a reachable
`ForeignFunctionInterface` and follows the ordinary `once` rules.

- `monotonic_now(.self: &Clock = reach clock)` returns
  `Errable<MonotonicInstant, clock_read_failed/out_of_range>`.
- `wall_now(.self: &Clock = reach clock)` returns
  `Errable<UnixTimestamp, clock_read_failed/out_of_range>`.
- `sleep(.duration: Duration, .self: &Clock = reach clock)` returns
  `Errable<Void, sleep_failed>`.

A failed platform read reports `clock_read_failed`; a successful monotonic
reading exceeding the nanosecond representation reports `out_of_range`.
Sleeping for zero succeeds immediately. A positive sleep blocks the calling
thread for at least the requested interval on success, but may resume later
because of scheduling. It is not an async timer or a scheduler yield.
Interrupted waits continue with their remaining interval; failures return
`sleep_failed`.

```rg
main(.system: System) -> (.status_code: Int32 = 0) := {
    assume clock ::= system.clock
    start ::= unwrap_or_abort(.value = monotonic_now()).result
    delay ::= unwrap_or_abort(.value = Duration(.milliseconds = 10)).result
    unwrap_or_abort(.value = sleep(.duration = delay))
    end ::= unwrap_or_abort(.value = monotonic_now()).result
    interval ::= unwrap_or_abort(.value = elapsed(.start = start, .end = end)).result
    civil ::= unwrap_or_abort(.value = wall_now()).result
}
```
