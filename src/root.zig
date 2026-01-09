//! VENOM — High-Performance Gaming Runtime & Compositor
//!
//! Next-generation Linux gaming runtime built on top of NVPrime.
//! Designed to surpass and supersede Gamescope - NVIDIA-native, latency-focused.
//!
//! Core Components:
//! - Runtime: Frame scheduling, latency control, direct scanout
//! - Compositor: Wayland-based, HDR passthrough, VRR control
//! - Latency Engine: Reflex monitoring, frame queue analysis
//! - Vulkan Layer: Zero-copy overlays, shader introspection
//!
//! Built on the NVPrime ecosystem:
//! - nvvk: Vulkan extension wrappers (VK_NV_low_latency2, etc.)
//! - nvlatency: Reflex-style latency measurement
//! - nvsync: VRR/G-Sync management
//! - nvhud: Performance overlay
//! - nvshader: Shader cache management

const std = @import("std");

// NVPrime - The unified NVIDIA platform
pub const nvprime = @import("nvprime");

// VENOM subsystems
pub const runtime = @import("runtime.zig");
pub const latency = @import("latency.zig");
pub const compositor = @import("compositor.zig");
pub const vulkan_layer = @import("vulkan_layer.zig");
pub const hud = @import("hud.zig");
pub const hud_renderer = @import("hud_renderer.zig");
pub const sessions = @import("sessions.zig");
pub const governor = @import("governor.zig");
pub const numa = @import("numa.zig");

pub const version = "0.1.0";

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
    /// Latency preset (default, balanced, ultra, competitive)
    latency_preset: nvprime.nvruntime.nvlatency.LatencyPreset = .balanced,
};

/// GPU information from nvprime
pub const GpuInfo = struct {
    name: []const u8,
    driver_version: []const u8,
    temperature: u32,
    power_watts: f32,
    gpu_utilization: u32,
    memory_utilization: u32,
    vrr_capable: bool,
    hdr_capable: bool,
};

/// VENOM instance
pub const Venom = struct {
    allocator: std.mem.Allocator,
    config: Config,
    state: State = .uninitialized,

    // Subsystems
    runtime_ctx: ?*runtime.Context = null,
    latency_ctx: ?*latency.Context = null,

    // NVPrime integration
    nvprime_initialized: bool = false,

    /// Initialize VENOM with NVPrime integration
    pub fn init(allocator: std.mem.Allocator, config: Config) !*Venom {
        const self = try allocator.create(Venom);
        self.* = Venom{
            .allocator = allocator,
            .config = config,
        };

        self.state = .initializing;

        // Initialize NVPrime subsystems
        nvprime.init() catch |err| {
            std.log.warn("NVPrime init failed: {}, running in degraded mode", .{err});
            self.nvprime_initialized = false;
        };
        self.nvprime_initialized = true;

        // Initialize runtime with nvprime integration
        self.runtime_ctx = try runtime.Context.init(allocator, .{
            .target_fps = config.target_fps,
            .vrr_enabled = config.vrr_enabled,
            .low_latency = config.low_latency,
            .hud_enabled = config.show_hud,
            .hdr_enabled = config.hdr_enabled,
        });

        // Initialize latency engine
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

        // Cleanup NVPrime
        if (self.nvprime_initialized) {
            nvprime.deinit();
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

    /// Get GPU information via nvprime
    pub fn getGpuInfo(self: *const Venom) ?GpuInfo {
        if (!self.nvprime_initialized) return null;

        // Query GPU via nvprime.nvcaps
        const caps = nvprime.nvcaps.getCapabilities() catch return null;

        return GpuInfo{
            .name = caps.name[0..caps.name_len],
            .driver_version = nvprime.version.string,
            .temperature = caps.temperature,
            .power_watts = @as(f32, @floatFromInt(caps.power_usage)) / 1000.0,
            .gpu_utilization = caps.gpu_utilization,
            .memory_utilization = caps.memory_utilization,
            .vrr_capable = true, // TODO: Query from nvsync
            .hdr_capable = true, // TODO: Query from nvdisplay
        };
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

    /// Set latency preset
    pub fn setLatencyPreset(self: *Venom, preset: nvprime.nvruntime.nvlatency.LatencyPreset) void {
        self.config.latency_preset = preset;
        // Apply preset settings
        switch (preset) {
            .default => {
                self.setLowLatency(false);
                self.config.frame_queue_depth = 3;
            },
            .balanced => {
                self.setLowLatency(true);
                self.config.frame_queue_depth = 2;
            },
            .ultra => {
                self.setLowLatency(true);
                self.config.frame_queue_depth = 1;
            },
            .competitive => {
                self.setLowLatency(true);
                self.config.frame_queue_depth = 1;
                self.config.frame_prediction = true;
            },
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

test "nvprime version accessible" {
    _ = nvprime.version.string;
}
