const std = @import("std");

pub const Pass = enum { binding_types, assignment_values, dereferences, addresses, generic_types, error_candidates, checkpoint, resolution, completion, unit_verification, checking };

/// Optional diagnostic counters, owned by the benchmark rather than semantic
/// transactions. Rejected/speculative work remains observable after rollback.
/// A visit is one outer pool entry, not a nested type/effect traversal.
pub const Profile = struct {
    pub const Entry = struct { calls: u64 = 0, visits: u64 = 0, changed: u64 = 0, ns: u64 = 0 };
    io: std.Io,
    entries: [@typeInfo(Pass).@"enum".fields.len]Entry = @splat(.{}),
    rounds: u64 = 0,

    pub const Measurement = struct {
        profile: *Profile,
        pass: Pass,
        started: i96,
        pub fn visit(self: Measurement, count: usize) void {
            self.profile.entries[@intFromEnum(self.pass)].visits += count;
        }
        pub fn finish(self: Measurement, changed: bool) void {
            const entry = &self.profile.entries[@intFromEnum(self.pass)];
            entry.changed += @intFromBool(changed);
            entry.ns += @intCast(@max(0, std.Io.Timestamp.now(self.profile.io, .boot).nanoseconds - self.started));
        }
    };

    pub fn begin(self: *Profile, pass: Pass) Measurement {
        self.entries[@intFromEnum(pass)].calls += 1;
        return .{ .profile = self, .pass = pass, .started = std.Io.Timestamp.now(self.io, .boot).nanoseconds };
    }
};
