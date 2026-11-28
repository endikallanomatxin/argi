const tok = @import("../../2_tokens/token.zig");

pub const Initializedness = enum {
    initialized,
    maybe_initialized,
    moved,
    deinitialized,
};

/// Possible initialization states of one fixed storage slot. A strong
/// write selects one case. A join preserves every reaching case.
pub const Initialization = packed struct(u3) {
    initialized: bool = false,
    moved: bool = false,
    deinitialized: bool = false,

    pub fn fromLegacy(state: Initializedness) Initialization {
        return switch (state) {
            .initialized => .{ .initialized = true },
            .moved => .{ .moved = true },
            .deinitialized => .{ .deinitialized = true },
            .maybe_initialized => .{ .initialized = true, .moved = true, .deinitialized = true },
        };
    }

    pub fn toLegacy(self: Initialization) Initializedness {
        return switch (@as(u3, @bitCast(self))) {
            1 => .initialized,
            2 => .moved,
            4 => .deinitialized,
            else => .maybe_initialized,
        };
    }

    pub fn join(left: Initialization, right: Initialization) Initialization {
        return @bitCast(@as(u3, @bitCast(left)) | @as(u3, @bitCast(right)));
    }

    pub fn covers(self: Initialization, incoming: Initialization) bool {
        return @as(u3, @bitCast(self.join(incoming))) == @as(u3, @bitCast(self));
    }

    pub fn definitelyInitialized(self: Initialization) bool {
        return self.initialized and !self.moved and !self.deinitialized;
    }

    pub fn weakWrite(self: Initialization, written: Initialization) Initialization {
        return self.join(written);
    }
};

test "safety initialization weak writes preserve all reaching states" {
    const testing = @import("std").testing;
    const written = Initialization.fromLegacy(.initialized);
    for (0..8) |a| for (0..8) |b| {
        const left: Initialization = @bitCast(@as(u3, @intCast(a)));
        const right: Initialization = @bitCast(@as(u3, @intCast(b)));
        const joined = left.join(right);
        try testing.expect(joined.covers(left) and joined.covers(right));
        try testing.expectEqual(joined.weakWrite(written), left.weakWrite(written).join(right.weakWrite(written)));
        try testing.expectEqual(a == 1, left.definitelyInitialized());
    };
}

/// Compatibility projection for state tables that still use the four-case
/// representation. Keep the exact cases in the finite domain itself.
pub fn joinInitializedness(left: Initializedness, right: Initializedness) Initializedness {
    return Initialization.fromLegacy(left).join(Initialization.fromLegacy(right)).toLegacy();
}

pub const State = struct {
    initializedness: Initializedness = .initialized,
    transition_location: ?tok.Location = null,
};
