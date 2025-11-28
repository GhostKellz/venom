//! VENOM Latency Engine — Reflex-style Latency Control
//!
//! Deep NVIDIA integration for latency monitoring and optimization.
//! Monitors frame queues, GPU scheduling, and input-to-display pipeline.

const std = @import("std");

/// Latency engine configuration
pub const Config = struct {
    frame_queue_depth: u8 = 2,
    prediction_enabled: bool = false,
};

/// Latency statistics
pub const Stats = struct {
    /// Total input-to-display latency (ms)
    total_latency_ms: f32 = 0,
    /// CPU frame time (ms)
    cpu_time_ms: f32 = 0,
    /// GPU render time (ms)
    gpu_time_ms: f32 = 0,
    /// Frame queue wait time (ms)
    queue_time_ms: f32 = 0,
    /// Compositor overhead (ms)
    compositor_ms: f32 = 0,
    /// Display scanout time (ms)
    scanout_ms: f32 = 0,
    /// Predicted next frame latency (ms)
    predicted_ms: f32 = 0,
};

/// Frame timing sample
pub const FrameSample = struct {
    frame_id: u64 = 0,
    input_ns: u64 = 0,
    cpu_start_ns: u64 = 0,
    cpu_end_ns: u64 = 0,
    gpu_submit_ns: u64 = 0,
    gpu_complete_ns: u64 = 0,
    present_ns: u64 = 0,
    scanout_ns: u64 = 0,

    pub fn totalLatencyNs(self: *const FrameSample) u64 {
        if (self.scanout_ns > self.input_ns) {
            return self.scanout_ns - self.input_ns;
        }
        if (self.present_ns > self.input_ns) {
            return self.present_ns - self.input_ns;
        }
        return 0;
    }

    pub fn cpuTimeNs(self: *const FrameSample) u64 {
        if (self.cpu_end_ns > self.cpu_start_ns) {
            return self.cpu_end_ns - self.cpu_start_ns;
        }
        return 0;
    }

    pub fn gpuTimeNs(self: *const FrameSample) u64 {
        if (self.gpu_complete_ns > self.gpu_submit_ns) {
            return self.gpu_complete_ns - self.gpu_submit_ns;
        }
        return 0;
    }
};

/// Rolling latency buffer
fn LatencyBuffer(comptime N: usize) type {
    return struct {
        const Self = @This();

        samples: [N]FrameSample = [_]FrameSample{.{}} ** N,
        index: usize = 0,
        count: usize = 0,

        pub fn push(self: *Self, sample: FrameSample) void {
            self.samples[self.index] = sample;
            self.index = (self.index + 1) % N;
            if (self.count < N) self.count += 1;
        }

        pub fn averageLatencyMs(self: *const Self) f32 {
            if (self.count == 0) return 0;
            var sum: u64 = 0;
            for (self.samples[0..self.count]) |s| {
                sum += s.totalLatencyNs();
            }
            return @as(f32, @floatFromInt(sum / self.count)) / 1_000_000.0;
        }

        pub fn averageCpuMs(self: *const Self) f32 {
            if (self.count == 0) return 0;
            var sum: u64 = 0;
            for (self.samples[0..self.count]) |s| {
                sum += s.cpuTimeNs();
            }
            return @as(f32, @floatFromInt(sum / self.count)) / 1_000_000.0;
        }

        pub fn averageGpuMs(self: *const Self) f32 {
            if (self.count == 0) return 0;
            var sum: u64 = 0;
            for (self.samples[0..self.count]) |s| {
                sum += s.gpuTimeNs();
            }
            return @as(f32, @floatFromInt(sum / self.count)) / 1_000_000.0;
        }

        pub fn latest(self: *const Self) ?FrameSample {
            if (self.count == 0) return null;
            const idx = if (self.index == 0) N - 1 else self.index - 1;
            return self.samples[idx];
        }
    };
}

/// Latency context
pub const Context = struct {
    allocator: std.mem.Allocator,
    config: Config,

    // Frame tracking
    current_frame_id: u64 = 0,
    low_latency_enabled: bool = true,

    // Latency history (120 samples ~ 2 seconds at 60fps)
    history: LatencyBuffer(120) = .{},

    // Frame prediction
    predicted_latency_ms: f32 = 0,

    pub fn init(allocator: std.mem.Allocator, config: Config) !*Context {
        const self = try allocator.create(Context);
        self.* = Context{
            .allocator = allocator,
            .config = config,
        };
        return self;
    }

    pub fn deinit(self: *Context) void {
        self.allocator.destroy(self);
    }

    /// Record a frame timing sample
    pub fn recordSample(self: *Context, sample: FrameSample) void {
        self.history.push(sample);
        self.current_frame_id = sample.frame_id;

        if (self.config.prediction_enabled) {
            self.updatePrediction();
        }
    }

    /// Begin tracking a new frame
    pub fn beginFrame(self: *Context) u64 {
        self.current_frame_id += 1;
        return self.current_frame_id;
    }

    /// Get current latency statistics
    pub fn getStats(self: *const Context) Stats {
        return Stats{
            .total_latency_ms = self.history.averageLatencyMs(),
            .cpu_time_ms = self.history.averageCpuMs(),
            .gpu_time_ms = self.history.averageGpuMs(),
            .predicted_ms = self.predicted_latency_ms,
        };
    }

    pub fn setLowLatency(self: *Context, enabled: bool) void {
        self.low_latency_enabled = enabled;
    }

    fn updatePrediction(self: *Context) void {
        // Simple EMA-based prediction
        const current = self.history.averageLatencyMs();
        const alpha: f32 = 0.3;
        self.predicted_latency_ms = alpha * current + (1.0 - alpha) * self.predicted_latency_ms;
    }

    /// Get recommended frame queue depth based on latency
    pub fn getRecommendedQueueDepth(self: *const Context) u8 {
        const avg_latency = self.history.averageLatencyMs();

        // Lower queue depth for lower latency
        if (self.low_latency_enabled) {
            return 1;
        }

        // Adaptive: increase queue for consistency at high latency
        if (avg_latency > 30.0) return 3;
        if (avg_latency > 20.0) return 2;
        return 1;
    }
};

test "latency stats" {
    const stats = Stats{};
    try std.testing.expectEqual(@as(f32, 0), stats.total_latency_ms);
}

test "frame sample latency" {
    const sample = FrameSample{
        .input_ns = 1000,
        .scanout_ns = 2000,
    };
    try std.testing.expectEqual(@as(u64, 1000), sample.totalLatencyNs());
}
