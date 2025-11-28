//! VENOM Runtime — Frame Scheduling & Game Execution
//!
//! Handles frame timing, VRR coordination, and game process management.
//! Integrates with PrimeTime compositor for direct scanout.

const std = @import("std");

/// Get current time in nanoseconds
fn getCurrentTimeNs() u64 {
    const now = std.time.Instant.now() catch return 0;
    const sec: u64 = @intCast(now.timestamp.sec);
    const nsec: u64 = @intCast(now.timestamp.nsec);
    return sec * 1_000_000_000 + nsec;
}

/// Runtime configuration
pub const Config = struct {
    target_fps: u32 = 0,
    vrr_enabled: bool = true,
    low_latency: bool = true,
};

/// Frame statistics
pub const FrameStats = struct {
    /// Current FPS
    fps: f32 = 0,
    /// Average frame time (ms)
    frame_time_ms: f32 = 0,
    /// 1% low FPS
    one_percent_low: f32 = 0,
    /// 0.1% low FPS
    point_one_low: f32 = 0,
    /// Frame number
    frame_count: u64 = 0,
    /// Current VRR refresh rate
    vrr_hz: u32 = 0,
};

/// Rolling statistics buffer
fn RollingBuffer(comptime N: usize) type {
    return struct {
        const Self = @This();

        values: [N]f32 = [_]f32{0} ** N,
        index: usize = 0,
        count: usize = 0,

        pub fn push(self: *Self, value: f32) void {
            self.values[self.index] = value;
            self.index = (self.index + 1) % N;
            if (self.count < N) self.count += 1;
        }

        pub fn average(self: *const Self) f32 {
            if (self.count == 0) return 0;
            var sum: f32 = 0;
            for (self.values[0..self.count]) |v| sum += v;
            return sum / @as(f32, @floatFromInt(self.count));
        }

        pub fn percentile(self: *const Self, p: f32) f32 {
            if (self.count == 0) return 0;
            if (self.count == 1) return self.values[0];

            var sorted: [N]f32 = undefined;
            @memcpy(sorted[0..self.count], self.values[0..self.count]);
            std.mem.sort(f32, sorted[0..self.count], {}, std.sort.asc(f32));

            const idx = @as(usize, @intFromFloat(@as(f32, @floatFromInt(self.count - 1)) * p / 100.0));
            return sorted[idx];
        }
    };
}

/// Runtime context
pub const Context = struct {
    allocator: std.mem.Allocator,
    config: Config,
    running: bool = false,

    // Frame timing
    target_frame_ns: u64 = 0,
    last_frame_ns: u64 = 0,
    frame_count: u64 = 0,

    // Statistics (300 frames ~ 5 seconds at 60fps)
    frame_times: RollingBuffer(300) = .{},

    // Game process
    game_pid: ?std.posix.pid_t = null,

    pub fn init(allocator: std.mem.Allocator, config: Config) !*Context {
        const self = try allocator.create(Context);
        self.* = Context{
            .allocator = allocator,
            .config = config,
            .target_frame_ns = if (config.target_fps > 0) 1_000_000_000 / config.target_fps else 0,
        };
        return self;
    }

    pub fn deinit(self: *Context) void {
        self.stop();
        self.allocator.destroy(self);
    }

    pub fn start(self: *Context) !void {
        self.running = true;
        self.last_frame_ns = getCurrentTimeNs();
    }

    pub fn stop(self: *Context) void {
        self.running = false;

        // Kill game if running
        if (self.game_pid) |pid| {
            std.posix.kill(pid, std.posix.SIG.TERM) catch {};
            self.game_pid = null;
        }
    }

    pub fn launchGame(self: *Context, argv: []const []const u8) !void {
        var child_env = try std.process.getEnvMap(self.allocator);
        defer child_env.deinit();

        // Set NVIDIA gaming environment variables
        try child_env.put("__GL_GSYNC_ALLOWED", if (self.config.vrr_enabled) "1" else "0");
        try child_env.put("__GL_VRR_ALLOWED", if (self.config.vrr_enabled) "1" else "0");

        if (self.config.low_latency) {
            try child_env.put("__GL_MaxFramesAllowed", "1");
            try child_env.put("DXVK_FRAME_RATE", "0"); // Let VENOM handle limiting
        }

        // Spawn game
        var child = std.process.Child.init(argv, self.allocator);
        child.env_map = &child_env;

        try child.spawn();
        self.game_pid = child.id;
    }

    pub fn recordFrame(self: *Context, frame_time_ns: u64) void {
        const frame_time_ms = @as(f32, @floatFromInt(frame_time_ns)) / 1_000_000.0;
        self.frame_times.push(frame_time_ms);
        self.frame_count += 1;
        self.last_frame_ns = getCurrentTimeNs();
    }

    pub fn getFrameStats(self: *const Context) FrameStats {
        const avg_frame_time = self.frame_times.average();
        const fps = if (avg_frame_time > 0) 1000.0 / avg_frame_time else 0;

        const worst_1pct = self.frame_times.percentile(99);
        const worst_01pct = self.frame_times.percentile(99.9);

        return FrameStats{
            .fps = fps,
            .frame_time_ms = avg_frame_time,
            .one_percent_low = if (worst_1pct > 0) 1000.0 / worst_1pct else 0,
            .point_one_low = if (worst_01pct > 0) 1000.0 / worst_01pct else 0,
            .frame_count = self.frame_count,
        };
    }

    pub fn setTargetFps(self: *Context, fps: u32) void {
        self.config.target_fps = fps;
        self.target_frame_ns = if (fps > 0) 1_000_000_000 / fps else 0;
    }

    pub fn setLowLatency(self: *Context, enabled: bool) void {
        self.config.low_latency = enabled;
    }

    pub fn isGameRunning(self: *const Context) bool {
        if (self.game_pid) |pid| {
            const result = std.posix.kill(pid, 0);
            return result != error.NoSuchProcess;
        }
        return false;
    }
};

test "runtime config" {
    const config = Config{ .target_fps = 144 };
    try std.testing.expectEqual(@as(u32, 144), config.target_fps);
}

test "rolling buffer" {
    var buf: RollingBuffer(10) = .{};
    buf.push(10.0);
    buf.push(20.0);
    buf.push(30.0);
    try std.testing.expectEqual(@as(f32, 20.0), buf.average());
}
