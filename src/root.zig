//! VENOM — High-Performance Gaming Runtime & Compositor
//!
//! Next-generation Linux gaming runtime built on top of NVPrime.
//! Designed to be the "Gamescope killer" - NVIDIA-native, latency-focused.
//!
//! Core Components:
//! - Runtime: Frame scheduling, latency control, direct scanout
//! - Compositor: Wayland-based, HDR passthrough, VRR control
//! - Latency Engine: Reflex monitoring, frame queue analysis
//! - Vulkan Layer: Zero-copy overlays, shader introspection

const std = @import("std");

pub const runtime = @import("runtime.zig");
pub const latency = @import("latency.zig");
pub const compositor = @import("compositor.zig");
pub const vulkan_layer = @import("vulkan_layer.zig");

pub const version = "0.1.0-dev";

/// VENOM runtime state
pub const State = enum {
    uninitialized,
    initializing,
    ready,
    running,
    suspended,
    shutting_down,
    error_state,
};

/// VENOM configuration
pub const Config = struct {
    /// Enable low-latency mode (Reflex-like)
    low_latency: bool = true,
    /// Target frame rate (0 = unlimited)
    target_fps: u32 = 0,
    /// Enable VRR (G-Sync/FreeSync)
    vrr_enabled: bool = true,
    /// Enable HDR passthrough
    hdr_enabled: bool = true,
    /// Direct scanout mode (bypass compositor when possible)
    direct_scanout: bool = true,
    /// Enable performance overlay (VENOMHUD)
    show_hud: bool = false,
    /// Frame queue depth (1-3, lower = less latency, higher = smoother)
    frame_queue_depth: u8 = 2,
    /// Enable frame prediction
    frame_prediction: bool = false,
};

/// VENOM instance
pub const Venom = struct {
    allocator: std.mem.Allocator,
    config: Config,
    state: State = .uninitialized,

    // Subsystems
    runtime_ctx: ?*runtime.Context = null,
    latency_ctx: ?*latency.Context = null,

    /// Initialize VENOM
    pub fn init(allocator: std.mem.Allocator, config: Config) !*Venom {
        const self = try allocator.create(Venom);
        self.* = Venom{
            .allocator = allocator,
            .config = config,
        };

        self.state = .initializing;

        // Initialize subsystems
        self.runtime_ctx = try runtime.Context.init(allocator, .{
            .target_fps = config.target_fps,
            .vrr_enabled = config.vrr_enabled,
            .low_latency = config.low_latency,
        });

        self.latency_ctx = try latency.Context.init(allocator, .{
            .frame_queue_depth = config.frame_queue_depth,
            .prediction_enabled = config.frame_prediction,
        });

        self.state = .ready;
        return self;
    }

    /// Deinitialize VENOM
    pub fn deinit(self: *Venom) void {
        self.state = .shutting_down;

        if (self.latency_ctx) |ctx| {
            ctx.deinit();
        }
        if (self.runtime_ctx) |ctx| {
            ctx.deinit();
        }

        self.allocator.destroy(self);
    }

    /// Start the runtime (begin processing frames)
    pub fn start(self: *Venom) !void {
        if (self.state != .ready) return error.InvalidState;

        if (self.runtime_ctx) |ctx| {
            try ctx.start();
        }

        self.state = .running;
    }

    /// Stop the runtime
    pub fn stop(self: *Venom) void {
        if (self.state != .running) return;

        if (self.runtime_ctx) |ctx| {
            ctx.stop();
        }

        self.state = .ready;
    }

    /// Run a game through VENOM
    pub fn runGame(self: *Venom, argv: []const []const u8) !void {
        if (self.state != .running) {
            try self.start();
        }

        if (self.runtime_ctx) |ctx| {
            try ctx.launchGame(argv);
        }
    }

    /// Get current latency stats
    pub fn getLatencyStats(self: *const Venom) latency.Stats {
        if (self.latency_ctx) |ctx| {
            return ctx.getStats();
        }
        return .{};
    }

    /// Get current frame stats
    pub fn getFrameStats(self: *const Venom) runtime.FrameStats {
        if (self.runtime_ctx) |ctx| {
            return ctx.getFrameStats();
        }
        return .{};
    }

    /// Set frame rate limit
    pub fn setFrameLimit(self: *Venom, fps: u32) void {
        self.config.target_fps = fps;
        if (self.runtime_ctx) |ctx| {
            ctx.setTargetFps(fps);
        }
    }

    /// Enable/disable low latency mode
    pub fn setLowLatency(self: *Venom, enabled: bool) void {
        self.config.low_latency = enabled;
        if (self.runtime_ctx) |ctx| {
            ctx.setLowLatency(enabled);
        }
        if (self.latency_ctx) |ctx| {
            ctx.setLowLatency(enabled);
        }
    }
};

// ============================================================================
// Global instance for simple usage
// ============================================================================

var global_instance: ?*Venom = null;

/// Initialize global VENOM instance
pub fn init(allocator: std.mem.Allocator, config: Config) !void {
    if (global_instance != null) return error.AlreadyInitialized;
    global_instance = try Venom.init(allocator, config);
}

/// Deinitialize global instance
pub fn deinit() void {
    if (global_instance) |v| {
        v.deinit();
        global_instance = null;
    }
}

/// Get global instance
pub fn get() ?*Venom {
    return global_instance;
}

/// Quick start with default config
pub fn quickStart(allocator: std.mem.Allocator) !*Venom {
    return Venom.init(allocator, .{});
}

// ============================================================================
// Tests
// ============================================================================

test "venom config defaults" {
    const config = Config{};
    try std.testing.expect(config.low_latency);
    try std.testing.expect(config.vrr_enabled);
    try std.testing.expectEqual(@as(u8, 2), config.frame_queue_depth);
}

test "venom state transitions" {
    try std.testing.expectEqual(State.uninitialized, State.uninitialized);
}
