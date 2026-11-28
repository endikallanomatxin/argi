//! Observation evidence for one statically numbered production partition.
//! Storage identity, authority and custody belong to separate state components.
const std = @import("std");

pub const Observation = packed struct(u3) {
    current_live: bool = false,
    current_ended: bool = false,
    historical: bool = false,

    pub fn join(left: Observation, right: Observation) Observation {
        return @bitCast(@as(u3, @bitCast(left)) | @as(u3, @bitCast(right)));
    }

    pub fn covers(header: Observation, incoming: Observation) bool {
        return @as(u3, @bitCast(header.join(incoming))) == @as(u3, @bitCast(header));
    }

    /// Before producing a new singleton, move all evidence for its old
    /// incarnation to the history. History supplies no positive validity proof.
    pub fn age(old: Observation) Observation {
        return .{ .historical = old.historical or old.current_live or old.current_ended };
    }

    /// End all observations of the selected singleton, keeping any
    /// alternatives that belong to different incarnations.
    pub fn retireCurrent(old: Observation) Observation {
        return .{ .current_ended = old.current_ended or old.current_live, .historical = old.historical };
    }

    /// The caller checks known coverage of all target alternatives and the
    /// corresponding access authority separately.
    pub fn provesCurrent(self: Observation) bool {
        return self.current_live and !self.current_ended and !self.historical;
    }
};

test "loop observation transfers distribute over the finite join" {
    for (0..8) |a| for (0..8) |b| {
        const left: Observation = @bitCast(@as(u3, @intCast(a)));
        const right: Observation = @bitCast(@as(u3, @intCast(b)));
        const joined = left.join(right);
        try std.testing.expect(joined.covers(left) and joined.covers(right));
        try std.testing.expectEqual(joined, right.join(left));
        try std.testing.expectEqual(joined.age(), left.age().join(right.age()));
        try std.testing.expectEqual(joined.retireCurrent(), left.retireCurrent().join(right.retireCurrent()));
        try std.testing.expect(!left.age().provesCurrent());
        try std.testing.expect(!left.retireCurrent().provesCurrent());
        for (0..8) |c| {
            const upper: Observation = @bitCast(@as(u3, @intCast(c)));
            if (upper.covers(left) and upper.covers(right)) try std.testing.expect(upper.covers(joined));
        }
    };
}

test "loop observation of the previous singleton stays stale when a new singleton is produced" {
    const observed: Observation = .{ .current_live = true };
    const saved = observed.age();
    const renewed: Observation = .{ .current_live = true };
    try std.testing.expect(renewed.provesCurrent());
    try std.testing.expect(!saved.provesCurrent());
    try std.testing.expect(!saved.join(renewed).provesCurrent());
    try std.testing.expectEqual(saved, saved.age());
}
