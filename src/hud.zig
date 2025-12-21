//! VENOM HUD — Performance Overlay
//!
//! Integrates nvhud (via nvprime) to render performance metrics
//! as a compositor overlay. This is the compositor-side rendering
//! of nvhud's metrics and HUD content.
//!
//! The overlay is rendered by venom's compositor, not by a
//! separate Vulkan layer. This is similar to how gamescope
//! handles its overlay.

const std = @import("std");
const nvprime = @import("nvprime");

// nvhud types via nvprime
const nvhud = nvprime.nvhud;
const Overlay = nvhud.Overlay;
const Collector = nvhud.Collector;
const Config = nvhud.Config;
const RenderCommand = nvhud.RenderCommand;
const Color = nvhud.Color;
const Position = nvhud.Position;

/// HUD state
pub const State = enum {
    disabled,
    initializing,
    ready,
    error_state,
};

/// HUD configuration (extends nvhud config with venom-specific options)
pub const HudConfig = struct {
    /// Base nvhud config
    nvhud_config: Config = Config.gaming(),

    /// Show venom-specific latency info (from latency engine)
    show_venom_latency: bool = true,

    /// Show compositor stats (direct scanout, VRR status)
    show_compositor_stats: bool = false,

    /// Hotkey to toggle HUD (scancode)
    toggle_hotkey: u32 = 123, // F12

    /// Modifier for toggle (scancode, 0 = none)
    toggle_modifier: u32 = 54, // Right Shift

    pub fn default() HudConfig {
        return .{};
    }

    pub fn minimal() HudConfig {
        return .{
            .nvhud_config = Config.minimal(),
            .show_venom_latency = false,
            .show_compositor_stats = false,
        };
    }

    pub fn full() HudConfig {
        return .{
            .nvhud_config = Config.full(),
            .show_venom_latency = true,
            .show_compositor_stats = true,
        };
    }
};

/// Venom latency stats (from latency engine)
pub const VenomLatencyStats = struct {
    /// Total input-to-display latency (ms)
    total_latency_ms: f32 = 0,
    /// Render latency (ms)
    render_latency_ms: f32 = 0,
    /// Present latency (ms)
    present_latency_ms: f32 = 0,
    /// Frame queue depth
    queue_depth: u8 = 0,
    /// Reflex enabled
    reflex_enabled: bool = false,
};

/// Compositor stats for HUD display
pub const CompositorStats = struct {
    /// Direct scanout active
    direct_scanout: bool = false,
    /// VRR active
    vrr_active: bool = false,
    /// HDR active
    hdr_active: bool = false,
    /// Tearing allowed
    tearing_active: bool = false,
    /// Current refresh rate (Hz)
    refresh_hz: u32 = 0,
};

/// HUD context
pub const Hud = struct {
    allocator: std.mem.Allocator,
    config: HudConfig,
    state: State = .disabled,

    // nvhud components
    overlay: ?Overlay = null,
    collector: ?Collector = null,

    // Visibility
    visible: bool = true,

    // Venom-specific stats (set externally)
    venom_latency: VenomLatencyStats = .{},
    compositor_stats: CompositorStats = .{},

    // Extra HUD lines for venom stats
    extra_lines_buf: [8][64]u8 = undefined,
    extra_lines_count: usize = 0,

    const Self = @This();

    /// Initialize HUD with nvhud integration
    pub fn init(allocator: std.mem.Allocator, config: HudConfig) !*Self {
        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .config = config,
        };

        self.state = .initializing;

        // Check if NVIDIA GPU available
        if (!nvhud.isOverlayAvailable()) {
            std.log.warn("NVIDIA GPU not available, HUD will run in degraded mode", .{});
        }

        // Create metrics collector
        self.collector = nvhud.createCollector();

        // Create overlay with config
        self.overlay = nvhud.createOverlayWithConfig(allocator, config.nvhud_config);

        self.state = .ready;
        std.log.info("VENOM HUD initialized", .{});

        return self;
    }

    /// Deinitialize HUD
    pub fn deinit(self: *Self) void {
        if (self.overlay) |*o| {
            o.deinit();
        }
        if (self.collector) |*c| {
            c.deinit();
        }
        self.allocator.destroy(self);
    }

    /// Toggle HUD visibility
    pub fn toggle(self: *Self) void {
        self.visible = !self.visible;
        if (self.overlay) |*o| {
            o.toggle();
        }
        std.log.debug("HUD visibility: {}", .{self.visible});
    }

    /// Set visibility
    pub fn setVisible(self: *Self, visible: bool) void {
        self.visible = visible;
        if (self.overlay) |*o| {
            o.visible = visible;
        }
    }

    /// Update venom latency stats (called by latency engine)
    pub fn updateLatencyStats(self: *Self, stats: VenomLatencyStats) void {
        self.venom_latency = stats;
    }

    /// Update compositor stats
    pub fn updateCompositorStats(self: *Self, stats: CompositorStats) void {
        self.compositor_stats = stats;
    }

    /// Record frame time (call once per frame)
    pub fn recordFrame(self: *Self) void {
        if (self.overlay) |*o| {
            o.recordFrame();
        }
    }

    /// Update metrics (call periodically, not every frame)
    pub fn updateMetrics(self: *Self) void {
        if (self.overlay) |*o| {
            o.updateMetrics();
        }
    }

    /// Build HUD content and generate render commands
    pub fn buildHud(self: *Self, screen_width: u32, screen_height: u32) void {
        if (self.overlay) |*o| {
            // Build nvhud content (FPS, GPU metrics, etc.)
            o.buildHud();

            // Generate render commands
            o.generateCommands(screen_width, screen_height);
        }

        // Build extra lines for venom-specific stats
        self.buildExtraLines();
    }

    /// Build venom-specific HUD lines
    fn buildExtraLines(self: *Self) void {
        self.extra_lines_count = 0;

        // Latency stats
        if (self.config.show_venom_latency and self.venom_latency.total_latency_ms > 0) {
            const line = std.fmt.bufPrint(
                &self.extra_lines_buf[self.extra_lines_count],
                "Latency: {d:.1}ms",
                .{self.venom_latency.total_latency_ms},
            ) catch return;
            _ = line;
            self.extra_lines_count += 1;

            if (self.venom_latency.reflex_enabled) {
                const reflex_line = std.fmt.bufPrint(
                    &self.extra_lines_buf[self.extra_lines_count],
                    "Reflex: ON",
                    .{},
                ) catch return;
                _ = reflex_line;
                self.extra_lines_count += 1;
            }
        }

        // Compositor stats
        if (self.config.show_compositor_stats) {
            if (self.compositor_stats.direct_scanout) {
                const ds_line = std.fmt.bufPrint(
                    &self.extra_lines_buf[self.extra_lines_count],
                    "Direct Scanout",
                    .{},
                ) catch return;
                _ = ds_line;
                self.extra_lines_count += 1;
            }

            if (self.compositor_stats.vrr_active) {
                const vrr_line = std.fmt.bufPrint(
                    &self.extra_lines_buf[self.extra_lines_count],
                    "VRR: {d}Hz",
                    .{self.compositor_stats.refresh_hz},
                ) catch return;
                _ = vrr_line;
                self.extra_lines_count += 1;
            }
        }
    }

    /// Get render commands from nvhud overlay
    pub fn getRenderCommands(self: *const Self) []const RenderCommand {
        if (self.overlay) |*o| {
            return o.getCommands();
        }
        return &[_]RenderCommand{};
    }

    /// Get extra lines count
    pub fn getExtraLinesCount(self: *const Self) usize {
        return self.extra_lines_count;
    }

    /// Get extra line text
    pub fn getExtraLine(self: *const Self, index: usize) ?[]const u8 {
        if (index >= self.extra_lines_count) return null;
        const buf = &self.extra_lines_buf[index];
        // Find null terminator or end
        for (buf, 0..) |c, i| {
            if (c == 0) return buf[0..i];
        }
        return buf[0..];
    }

    /// Check if HUD should be rendered
    pub fn shouldRender(self: *const Self) bool {
        return self.visible and self.state == .ready;
    }

    /// Get nvhud config
    pub fn getNvhudConfig(self: *const Self) Config {
        return self.config.nvhud_config;
    }

    /// Set position
    pub fn setPosition(self: *Self, position: Position) void {
        self.config.nvhud_config.position = position;
        if (self.overlay) |*o| {
            o.cfg.position = position;
        }
    }

    /// Get GPU metrics (if collector available)
    pub fn getGpuMetrics(self: *const Self) ?nvhud.GpuMetrics {
        if (self.collector) |*c| {
            return c.collect();
        }
        return null;
    }
};

// ============================================================================
// Compositor Rendering Interface
// ============================================================================

/// Render command iterator for compositor
pub const RenderIterator = struct {
    commands: []const RenderCommand,
    index: usize = 0,

    pub fn next(self: *RenderIterator) ?RenderCommand {
        if (self.index >= self.commands.len) return null;
        const cmd = self.commands[self.index];
        self.index += 1;
        return cmd;
    }

    pub fn reset(self: *RenderIterator) void {
        self.index = 0;
    }
};

/// Create iterator for render commands
pub fn createRenderIterator(hud: *const Hud) RenderIterator {
    return RenderIterator{
        .commands = hud.getRenderCommands(),
    };
}

// ============================================================================
// Tests
// ============================================================================

test "hud config defaults" {
    const config = HudConfig.default();
    try std.testing.expect(config.show_venom_latency);
    try std.testing.expect(!config.show_compositor_stats);
}

test "hud config presets" {
    const minimal = HudConfig.minimal();
    try std.testing.expect(!minimal.show_venom_latency);

    const full = HudConfig.full();
    try std.testing.expect(full.show_compositor_stats);
}
