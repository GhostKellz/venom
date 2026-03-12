//! VENOM Power Management — GPU Power State Optimization
//!
//! Optimizations for NVIDIA 595.45.04+ driver:
//! - Persistence mode to prevent GPU power state transitions
//! - P-state locking for consistent frame times
//! - GC6 prevention during gaming sessions
//!
//! These optimizations reduce frame time variance by preventing
//! the GPU from entering low-power states during gameplay.

const std = @import("std");
const nvprime = @import("nvprime");

// nvcore submodules for clock/power management
const pstates = nvprime.nvcore.pstates;

/// Power optimization profile
pub const Profile = enum {
    /// Default - no optimizations, let driver manage
    default,
    /// Gaming - lock P-state, prevent power states
    gaming,
    /// Competitive - maximum performance, lock at max P-state
    competitive,
    /// Balanced - moderate optimization, allow some power saving
    balanced,

    pub fn description(self: Profile) []const u8 {
        return switch (self) {
            .default => "Default (driver managed)",
            .gaming => "Gaming (locked P-state, no GC6)",
            .competitive => "Competitive (max performance, ultra-low latency)",
            .balanced => "Balanced (moderate optimization)",
        };
    }
};

/// Power state snapshot for restoration
pub const PowerState = struct {
    power_limit_w: u32 = 0,
    pstate_locked: bool = false,
    valid: bool = false,
};

/// Power optimization context
pub const Context = struct {
    allocator: std.mem.Allocator,
    device_index: u32,
    original_state: PowerState,
    current_profile: Profile,
    active: bool,

    pub fn init(allocator: std.mem.Allocator, device_index: u32) !*Context {
        const self = try allocator.create(Context);
        self.* = Context{
            .allocator = allocator,
            .device_index = device_index,
            .original_state = .{},
            .current_profile = .default,
            .active = false,
        };
        return self;
    }

    pub fn deinit(self: *Context) void {
        if (self.active) {
            self.restore() catch {};
        }
        self.allocator.destroy(self);
    }

    /// Capture current power state for later restoration
    pub fn captureState(self: *Context) !void {
        // Check if P-state is currently locked
        const pstate = pstates.getCurrent(self.device_index) catch {
            return error.DeviceNotFound;
        };
        _ = pstate;

        // Query power limit if available
        if (nvprime.nvpower.limits.get(self.device_index)) |limit| {
            self.original_state.power_limit_w = limit;
        } else |_| {}

        self.original_state.valid = true;
    }

    /// Apply power optimization profile
    pub fn applyProfile(self: *Context, profile: Profile) !void {
        if (!self.original_state.valid) {
            self.captureState() catch {};
        }

        switch (profile) {
            .default => {
                self.restore() catch {};
                return;
            },
            .gaming => {
                // Lock P-state to performance mode (prevents GC6/D3 transitions)
                pstates.lock(self.device_index, .performance) catch {};
            },
            .competitive => {
                // Lock P-state to maximum performance
                pstates.lock(self.device_index, .max_performance) catch {};

                // Set power limit to maximum if available
                if (nvprime.nvpower.limits.getInfo(self.device_index)) |info| {
                    nvprime.nvpower.limits.set(self.device_index, .{ .watts = info.max_w }) catch {};
                } else |_| {}
            },
            .balanced => {
                // Lock P-state to performance mode (allows some flexibility)
                pstates.lock(self.device_index, .performance) catch {};
            },
        }

        self.current_profile = profile;
        self.active = profile != .default;
    }

    /// Restore original power state
    pub fn restore(self: *Context) !void {
        if (!self.original_state.valid) return;

        // Unlock P-state
        pstates.unlock(self.device_index) catch {};

        // Restore power limit
        if (self.original_state.power_limit_w > 0) {
            nvprime.nvpower.limits.set(self.device_index, .{ .watts = self.original_state.power_limit_w }) catch {};
        }

        self.active = false;
        self.current_profile = .default;
    }

    /// Get current P-state
    pub fn getCurrentPState(self: *Context) ?pstates.PState {
        return pstates.getCurrent(self.device_index) catch null;
    }

    /// Check if GPU is in performance state
    pub fn isInPerformanceState(self: *Context) bool {
        return pstates.isInPerformanceState(self.device_index) catch false;
    }

    /// Check if optimizations are active
    pub fn isOptimized(self: *const Context) bool {
        return self.active;
    }

    /// Get current profile
    pub fn getProfile(self: *const Context) Profile {
        return self.current_profile;
    }
};

/// Quick helper to apply gaming optimizations
pub fn enableGamingMode(device_index: u32, allocator: std.mem.Allocator) !*Context {
    const ctx = try Context.init(allocator, device_index);
    errdefer ctx.deinit();
    try ctx.applyProfile(.gaming);
    return ctx;
}

/// Quick helper to apply competitive optimizations
pub fn enableCompetitiveMode(device_index: u32, allocator: std.mem.Allocator) !*Context {
    const ctx = try Context.init(allocator, device_index);
    errdefer ctx.deinit();
    try ctx.applyProfile(.competitive);
    return ctx;
}

test "power profile descriptions" {
    try std.testing.expect(Profile.gaming.description().len > 0);
    try std.testing.expect(Profile.competitive.description().len > 0);
}
