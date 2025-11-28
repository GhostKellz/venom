//! VENOM Compositor — Wayland Gaming Compositor
//!
//! Wayland-based compositor optimized for gaming.
//! Integrates with PrimeTime for HDR, VRR, and direct scanout.

const std = @import("std");

/// Compositor mode
pub const Mode = enum {
    /// Full compositor mode - handles all rendering
    full,
    /// Overlay mode - overlay on top of existing compositor
    overlay,
    /// Direct scanout - bypass compositor entirely
    direct,
    /// Nested - run inside another Wayland compositor
    nested,
};

/// HDR state
pub const HdrState = enum {
    disabled,
    enabled,
    passthrough,
};

/// Compositor configuration
pub const Config = struct {
    mode: Mode = .full,
    vrr_enabled: bool = true,
    hdr_state: HdrState = .passthrough,
    direct_scanout: bool = true,
    allow_tearing: bool = false,
    render_width: u32 = 0,
    render_height: u32 = 0,
    output_width: u32 = 0,
    output_height: u32 = 0,
};

/// Output/display information
pub const OutputInfo = struct {
    name: [64]u8 = [_]u8{0} ** 64,
    name_len: usize = 0,
    width: u32 = 0,
    height: u32 = 0,
    refresh_mhz: u32 = 0,
    vrr_capable: bool = false,
    hdr_capable: bool = false,

    pub fn getName(self: *const OutputInfo) []const u8 {
        return self.name[0..self.name_len];
    }

    pub fn refreshHz(self: *const OutputInfo) u32 {
        return self.refresh_mhz / 1000;
    }
};

/// Compositor state
pub const State = enum {
    uninitialized,
    initializing,
    ready,
    running,
    error_state,
};

/// Compositor context
pub const Context = struct {
    allocator: std.mem.Allocator,
    config: Config,
    state: State = .uninitialized,

    current_output: OutputInfo = .{},

    // Wayland socket name
    socket_name: [108]u8 = [_]u8{0} ** 108,
    socket_name_len: usize = 0,

    pub fn init(allocator: std.mem.Allocator, config: Config) !*Context {
        const self = try allocator.create(Context);
        self.* = Context{
            .allocator = allocator,
            .config = config,
        };

        self.state = .ready;
        return self;
    }

    pub fn deinit(self: *Context) void {
        if (self.state == .running) {
            self.stop();
        }
        self.allocator.destroy(self);
    }

    pub fn start(self: *Context) !void {
        if (self.state != .ready) return error.InvalidState;

        self.state = .initializing;

        // TODO: Initialize wlroots backend
        // 1. Create wl_display
        // 2. Create wlr_backend (DRM for direct, headless for nested)
        // 3. Create wlr_renderer
        // 4. Set up outputs
        // 5. Create scene graph
        // 6. Set up XDG shell

        self.state = .running;
    }

    pub fn stop(self: *Context) void {
        if (self.state != .running) return;

        // TODO: Cleanup wlroots resources

        self.state = .ready;
    }

    pub fn getSocketName(self: *const Context) ?[]const u8 {
        if (self.socket_name_len == 0) return null;
        return self.socket_name[0..self.socket_name_len];
    }

    pub fn getOutputInfo(self: *const Context) OutputInfo {
        return self.current_output;
    }

    pub fn setVrr(self: *Context, enabled: bool) void {
        self.config.vrr_enabled = enabled;
        // TODO: Apply to DRM connector
    }

    pub fn setHdr(self: *Context, state: HdrState) void {
        self.config.hdr_state = state;
        // TODO: Apply HDR metadata
    }

    pub fn setDirectScanout(self: *Context, enabled: bool) void {
        self.config.direct_scanout = enabled;
    }
};

test "compositor config" {
    const config = Config{};
    try std.testing.expect(config.vrr_enabled);
    try std.testing.expectEqual(Mode.full, config.mode);
}

test "output info" {
    var info = OutputInfo{
        .refresh_mhz = 144000,
    };
    try std.testing.expectEqual(@as(u32, 144), info.refreshHz());
}
