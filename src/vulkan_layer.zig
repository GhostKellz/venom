//! VENOM Vulkan Layer — Game Injection & Introspection
//!
//! Vulkan layer for game integration.
//! Enables zero-copy overlays, frame timing hooks, and shader introspection.
//! Works with native Vulkan, DXVK, and vkd3d-proton.

const std = @import("std");

/// Get current time in nanoseconds
fn getCurrentTimeNs() u64 {
    const now = std.time.Instant.now() catch return 0;
    const sec: u64 = @intCast(now.timestamp.sec);
    const nsec: u64 = @intCast(now.timestamp.nsec);
    return sec * 1_000_000_000 + nsec;
}

/// Layer features that can be enabled/disabled
pub const Features = struct {
    /// Enable frame timing hooks
    frame_timing: bool = true,
    /// Enable overlay rendering
    overlay: bool = false,
    /// Enable shader pipeline introspection
    shader_introspection: bool = false,
    /// Enable latency markers (Reflex-like)
    latency_markers: bool = true,
    /// Enable frame prediction
    frame_prediction: bool = false,
};

/// Frame timing data from Vulkan present
pub const FrameTiming = struct {
    frame_id: u64 = 0,
    cpu_present_ns: u64 = 0,
    gpu_start_ns: u64 = 0,
    gpu_end_ns: u64 = 0,
    actual_present_ns: u64 = 0,

    pub fn gpuTimeNs(self: *const FrameTiming) u64 {
        if (self.gpu_end_ns > self.gpu_start_ns) {
            return self.gpu_end_ns - self.gpu_start_ns;
        }
        return 0;
    }

    pub fn presentLatencyNs(self: *const FrameTiming) u64 {
        if (self.actual_present_ns > self.cpu_present_ns) {
            return self.actual_present_ns - self.cpu_present_ns;
        }
        return 0;
    }
};

/// Swapchain info captured from game
pub const SwapchainInfo = struct {
    width: u32 = 0,
    height: u32 = 0,
    format: u32 = 0, // VkFormat
    image_count: u32 = 0,
    present_mode: u32 = 0, // VkPresentModeKHR
    hdr_enabled: bool = false,
};

/// Latency marker types (Reflex-compatible)
pub const LatencyMarker = enum(u32) {
    simulation_start = 0,
    simulation_end = 1,
    rendersubmit_start = 2,
    rendersubmit_end = 3,
    present_start = 4,
    present_end = 5,
    input_sample = 6,
};

/// Layer context
pub const Context = struct {
    allocator: std.mem.Allocator,
    features: Features,
    enabled: bool = false,

    // Captured swapchain info
    swapchain: SwapchainInfo = .{},

    // Frame tracking
    current_frame_id: u64 = 0,
    frame_timings: [8]FrameTiming = [_]FrameTiming{.{}} ** 8,
    timing_index: usize = 0,

    pub fn init(allocator: std.mem.Allocator, features: Features) !*Context {
        const self = try allocator.create(Context);
        self.* = Context{
            .allocator = allocator,
            .features = features,
        };
        return self;
    }

    pub fn deinit(self: *Context) void {
        self.allocator.destroy(self);
    }

    pub fn enable(self: *Context) void {
        self.enabled = true;
    }

    pub fn disable(self: *Context) void {
        self.enabled = false;
    }

    /// Record a latency marker
    pub fn setLatencyMarker(self: *Context, marker: LatencyMarker) void {
        if (!self.features.latency_markers) return;

        const now = getCurrentTimeNs();
        const timing = &self.frame_timings[self.timing_index];

        switch (marker) {
            .simulation_start => {
                self.current_frame_id += 1;
                timing.frame_id = self.current_frame_id;
            },
            .rendersubmit_start => {
                timing.gpu_start_ns = now;
            },
            .rendersubmit_end => {
                timing.gpu_end_ns = now;
            },
            .present_start => {
                timing.cpu_present_ns = now;
            },
            .present_end => {
                timing.actual_present_ns = now;
                self.timing_index = (self.timing_index + 1) % 8;
            },
            else => {},
        }
    }

    /// Called when swapchain is created
    pub fn onSwapchainCreate(self: *Context, info: SwapchainInfo) void {
        self.swapchain = info;
    }

    /// Get latest frame timing
    pub fn getLatestTiming(self: *const Context) ?FrameTiming {
        const idx = if (self.timing_index == 0) 7 else self.timing_index - 1;
        const timing = self.frame_timings[idx];
        if (timing.frame_id == 0) return null;
        return timing;
    }

    /// Get average GPU time (ms)
    pub fn getAverageGpuMs(self: *const Context) f32 {
        var sum: u64 = 0;
        var count: u32 = 0;
        for (self.frame_timings) |t| {
            if (t.frame_id > 0) {
                sum += t.gpuTimeNs();
                count += 1;
            }
        }
        if (count == 0) return 0;
        return @as(f32, @floatFromInt(sum / count)) / 1_000_000.0;
    }

    /// Get average present latency (ms)
    pub fn getAveragePresentLatencyMs(self: *const Context) f32 {
        var sum: u64 = 0;
        var count: u32 = 0;
        for (self.frame_timings) |t| {
            if (t.frame_id > 0) {
                sum += t.presentLatencyNs();
                count += 1;
            }
        }
        if (count == 0) return 0;
        return @as(f32, @floatFromInt(sum / count)) / 1_000_000.0;
    }
};

/// Generate Vulkan layer manifest JSON
pub fn generateManifest(allocator: std.mem.Allocator) ![]const u8 {
    const manifest =
        \\{
        \\  "file_format_version": "1.0.0",
        \\  "layer": {
        \\    "name": "VK_LAYER_VENOM_performance",
        \\    "type": "GLOBAL",
        \\    "library_path": "./libvenom_layer.so",
        \\    "api_version": "1.3.0",
        \\    "implementation_version": "1",
        \\    "description": "VENOM Performance Layer - Low latency gaming",
        \\    "functions": {
        \\      "vkGetInstanceProcAddr": "venom_vkGetInstanceProcAddr",
        \\      "vkGetDeviceProcAddr": "venom_vkGetDeviceProcAddr"
        \\    }
        \\  }
        \\}
    ;
    return allocator.dupe(u8, manifest);
}

test "features defaults" {
    const features = Features{};
    try std.testing.expect(features.frame_timing);
    try std.testing.expect(features.latency_markers);
    try std.testing.expect(!features.overlay);
}

test "frame timing" {
    const timing = FrameTiming{
        .gpu_start_ns = 1000,
        .gpu_end_ns = 2000,
    };
    try std.testing.expectEqual(@as(u64, 1000), timing.gpuTimeNs());
}

test "latency marker enum" {
    try std.testing.expectEqual(@as(u32, 0), @intFromEnum(LatencyMarker.simulation_start));
    try std.testing.expectEqual(@as(u32, 6), @intFromEnum(LatencyMarker.input_sample));
}
