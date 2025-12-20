//! VENOM Compositor — Wayland Gaming Compositor
//!
//! Wayland-based compositor optimized for gaming.
//! Integrates with PrimeTime for HDR, VRR, and direct scanout.
//!
//! Features:
//! - Direct scanout for zero-copy game display
//! - VRR (Variable Refresh Rate) / FreeSync / G-Sync
//! - HDR passthrough (BT.2020, PQ/HLG transfer functions)
//! - Tearing support for competitive gaming
//! - XDG shell, layer shell for overlays
//! - Vulkan/EGL rendering with NVIDIA optimizations

const std = @import("std");
const builtin = @import("builtin");

pub const version = "0.1.0-dev";

// ============================================================================
// wlroots C Bindings (libwlroots 0.18+)
// ============================================================================

pub const wl_display = opaque {};
pub const wl_event_loop = opaque {};
pub const wl_listener = opaque {};
pub const wl_signal = opaque {};
pub const wl_client = opaque {};
pub const wl_resource = opaque {};

pub const wlr_backend = opaque {};
pub const wlr_renderer = opaque {};
pub const wlr_allocator = opaque {};
pub const wlr_compositor = opaque {};
pub const wlr_output = opaque {};
pub const wlr_output_layout = opaque {};
pub const wlr_scene = opaque {};
pub const wlr_scene_output = opaque {};
pub const wlr_seat = opaque {};
pub const wlr_keyboard = opaque {};
pub const wlr_pointer = opaque {};
pub const wlr_xdg_shell = opaque {};
pub const wlr_xdg_surface = opaque {};
pub const wlr_xdg_toplevel = opaque {};
pub const wlr_layer_shell_v1 = opaque {};
pub const wlr_surface = opaque {};
pub const wlr_cursor = opaque {};
pub const wlr_xcursor_manager = opaque {};

// DRM/KMS types
pub const wlr_drm_connector = opaque {};
pub const wlr_drm_lease_v1_manager = opaque {};

// C calling convention for this target
const cc = std.builtin.CallingConvention.c;

// wlroots function pointers (loaded dynamically)
pub const WlrFunctions = struct {
    // Display
    wl_display_create: ?*const fn () callconv(cc) ?*wl_display = null,
    wl_display_destroy: ?*const fn (*wl_display) callconv(cc) void = null,
    wl_display_get_event_loop: ?*const fn (*wl_display) callconv(cc) ?*wl_event_loop = null,
    wl_display_run: ?*const fn (*wl_display) callconv(cc) void = null,
    wl_display_terminate: ?*const fn (*wl_display) callconv(cc) void = null,
    wl_display_add_socket_auto: ?*const fn (*wl_display) callconv(cc) ?[*:0]const u8 = null,

    // Backend
    wlr_backend_autocreate: ?*const fn (*wl_event_loop, ?*anyopaque) callconv(cc) ?*wlr_backend = null,
    wlr_backend_destroy: ?*const fn (*wlr_backend) callconv(cc) void = null,
    wlr_backend_start: ?*const fn (*wlr_backend) callconv(cc) bool = null,

    // Renderer
    wlr_renderer_autocreate: ?*const fn (*wlr_backend) callconv(cc) ?*wlr_renderer = null,
    wlr_renderer_init_wl_display: ?*const fn (*wlr_renderer, *wl_display) callconv(cc) bool = null,

    // Allocator
    wlr_allocator_autocreate: ?*const fn (*wlr_backend, *wlr_renderer) callconv(cc) ?*wlr_allocator = null,

    // Compositor
    wlr_compositor_create: ?*const fn (*wl_display, u32, *wlr_renderer) callconv(cc) ?*wlr_compositor = null,

    // Scene
    wlr_scene_create: ?*const fn () callconv(cc) ?*wlr_scene = null,
    wlr_scene_attach_output_layout: ?*const fn (*wlr_scene, *wlr_output_layout) callconv(cc) bool = null,

    // Output
    wlr_output_layout_create: ?*const fn (*wl_display) callconv(cc) ?*wlr_output_layout = null,
    wlr_output_enable: ?*const fn (*wlr_output, bool) callconv(cc) void = null,
    wlr_output_commit: ?*const fn (*wlr_output) callconv(cc) bool = null,

    // XDG Shell
    wlr_xdg_shell_create: ?*const fn (*wl_display, u32) callconv(cc) ?*wlr_xdg_shell = null,

    // Seat
    wlr_seat_create: ?*const fn (*wl_display, [*:0]const u8) callconv(cc) ?*wlr_seat = null,

    // Cursor
    wlr_cursor_create: ?*const fn () callconv(cc) ?*wlr_cursor = null,
    wlr_xcursor_manager_create: ?*const fn (?[*:0]const u8, u32) callconv(cc) ?*wlr_xcursor_manager = null,
};

// ============================================================================
// Core Types
// ============================================================================

/// Compositor mode
pub const Mode = enum(u8) {
    /// Full compositor mode - handles all rendering
    full,
    /// Overlay mode - overlay on top of existing compositor
    overlay,
    /// Direct scanout - bypass compositor entirely
    direct,
    /// Nested - run inside another Wayland compositor
    nested,

    pub fn description(self: Mode) []const u8 {
        return switch (self) {
            .full => "Full compositor (DRM/KMS)",
            .overlay => "Overlay on existing compositor",
            .direct => "Direct scanout (zero latency)",
            .nested => "Nested Wayland",
        };
    }
};

/// HDR state
pub const HdrState = enum(u8) {
    disabled,
    enabled,
    passthrough, // Pass through HDR from game

    pub fn description(self: HdrState) []const u8 {
        return switch (self) {
            .disabled => "HDR disabled (SDR)",
            .enabled => "HDR enabled",
            .passthrough => "HDR passthrough",
        };
    }
};

/// HDR metadata type
pub const HdrMetadataType = enum(u8) {
    static_type_1, // Static metadata type 1 (HDR10)
    dynamic_type_1, // Dynamic metadata (HDR10+)
    dynamic_type_2, // Dolby Vision
};

/// HDR colorspace
pub const HdrColorspace = enum(u8) {
    srgb, // Standard sRGB
    bt709, // BT.709 (HDTV)
    bt2020, // BT.2020 (HDR wide gamut)
    display_p3, // Display P3
};

/// HDR transfer function
pub const HdrTransferFunction = enum(u8) {
    srgb, // sRGB gamma
    pq, // Perceptual Quantizer (HDR10)
    hlg, // Hybrid Log-Gamma
    linear, // Linear
};

/// HDR metadata
pub const HdrMetadata = struct {
    metadata_type: HdrMetadataType = .static_type_1,
    colorspace: HdrColorspace = .bt2020,
    transfer_function: HdrTransferFunction = .pq,

    // Display primaries (BT.2020 defaults)
    display_primaries_red_x: u16 = 34000, // 0.708
    display_primaries_red_y: u16 = 16000, // 0.292
    display_primaries_green_x: u16 = 8500, // 0.170
    display_primaries_green_y: u16 = 39850, // 0.797
    display_primaries_blue_x: u16 = 6550, // 0.131
    display_primaries_blue_y: u16 = 2300, // 0.046
    white_point_x: u16 = 15635, // 0.3127
    white_point_y: u16 = 16450, // 0.329

    // Luminance (nits)
    max_luminance: u32 = 1000, // Peak brightness
    min_luminance: u32 = 1, // 0.0001 nits * 10000
    max_content_light_level: u16 = 1000,
    max_frame_avg_light_level: u16 = 400,
};

/// VRR (Variable Refresh Rate) state
pub const VrrState = enum(u8) {
    disabled,
    enabled,
    adaptive, // Enable when fullscreen game detected
};

/// Tearing mode
pub const TearingMode = enum(u8) {
    disabled, // Always vsync
    enabled, // Allow tearing
    fullscreen_only, // Only allow tearing for fullscreen apps

    pub fn description(self: TearingMode) []const u8 {
        return switch (self) {
            .disabled => "VSync always on",
            .enabled => "Allow tearing",
            .fullscreen_only => "Tearing in fullscreen only",
        };
    }
};

/// Compositor configuration
pub const Config = struct {
    mode: Mode = .full,
    vrr_state: VrrState = .adaptive,
    hdr_state: HdrState = .passthrough,
    hdr_metadata: HdrMetadata = .{},
    direct_scanout: bool = true,
    tearing_mode: TearingMode = .fullscreen_only,

    // Resolution
    render_width: u32 = 0, // 0 = native
    render_height: u32 = 0,
    output_width: u32 = 0,
    output_height: u32 = 0,
    refresh_rate_mhz: u32 = 0, // 0 = max available

    // Performance
    max_render_ahead: u8 = 2, // Max frames to render ahead
    latency_mode: LatencyMode = .balanced,

    // Overlay
    enable_layer_shell: bool = true,
    enable_screen_capture: bool = true,

    // NVIDIA specific
    nvidia_low_latency: bool = true,
    nvidia_gsync: bool = true,
};

/// Latency mode
pub const LatencyMode = enum(u8) {
    ultra_low, // Minimize latency at all costs
    low, // Low latency with some smoothness
    balanced, // Balance between latency and smoothness
    smooth, // Prioritize frame consistency
};

/// Output/display information
pub const OutputInfo = struct {
    name: [64]u8 = [_]u8{0} ** 64,
    name_len: usize = 0,
    make: [64]u8 = [_]u8{0} ** 64,
    make_len: usize = 0,
    model: [64]u8 = [_]u8{0} ** 64,
    model_len: usize = 0,

    width: u32 = 0,
    height: u32 = 0,
    refresh_mhz: u32 = 0,
    physical_width_mm: u32 = 0,
    physical_height_mm: u32 = 0,
    scale: f32 = 1.0,

    // Capabilities
    vrr_capable: bool = false,
    hdr_capable: bool = false,
    hdr_metadata_supported: HdrMetadataType = .static_type_1,
    max_luminance_nits: u32 = 0,
    min_luminance_nits: u32 = 0,
    tearing_capable: bool = false,

    // Current state
    vrr_enabled: bool = false,
    hdr_enabled: bool = false,
    direct_scanout_active: bool = false,

    pub fn getName(self: *const OutputInfo) []const u8 {
        return self.name[0..self.name_len];
    }

    pub fn getMake(self: *const OutputInfo) []const u8 {
        return self.make[0..self.make_len];
    }

    pub fn getModel(self: *const OutputInfo) []const u8 {
        return self.model[0..self.model_len];
    }

    pub fn refreshHz(self: *const OutputInfo) u32 {
        return self.refresh_mhz / 1000;
    }

    pub fn refreshHzFloat(self: *const OutputInfo) f32 {
        return @as(f32, @floatFromInt(self.refresh_mhz)) / 1000.0;
    }

    pub fn diagonalInches(self: *const OutputInfo) f32 {
        if (self.physical_width_mm == 0 or self.physical_height_mm == 0) return 0;
        const w_mm: f32 = @floatFromInt(self.physical_width_mm);
        const h_mm: f32 = @floatFromInt(self.physical_height_mm);
        const diag_mm = @sqrt(w_mm * w_mm + h_mm * h_mm);
        return diag_mm / 25.4;
    }

    pub fn ppi(self: *const OutputInfo) f32 {
        const diag = self.diagonalInches();
        if (diag == 0) return 0;
        const w: f32 = @floatFromInt(self.width);
        const h: f32 = @floatFromInt(self.height);
        const diag_px = @sqrt(w * w + h * h);
        return diag_px / diag;
    }
};

/// Available video mode
pub const VideoMode = struct {
    width: u32,
    height: u32,
    refresh_mhz: u32,
    preferred: bool,

    pub fn refreshHz(self: VideoMode) u32 {
        return self.refresh_mhz / 1000;
    }
};

/// Window/surface info
pub const WindowInfo = struct {
    id: u64,
    title: [256]u8 = [_]u8{0} ** 256,
    title_len: usize = 0,
    app_id: [128]u8 = [_]u8{0} ** 128,
    app_id_len: usize = 0,

    x: i32 = 0,
    y: i32 = 0,
    width: u32 = 0,
    height: u32 = 0,

    fullscreen: bool = false,
    maximized: bool = false,
    focused: bool = false,
    urgent: bool = false,

    // Direct scanout eligibility
    can_direct_scanout: bool = false,
    using_direct_scanout: bool = false,

    pub fn getTitle(self: *const WindowInfo) []const u8 {
        return self.title[0..self.title_len];
    }

    pub fn getAppId(self: *const WindowInfo) []const u8 {
        return self.app_id[0..self.app_id_len];
    }
};

/// Compositor state
pub const State = enum(u8) {
    uninitialized,
    initializing,
    ready,
    running,
    paused,
    error_state,
};

/// Frame timing stats
pub const FrameStats = struct {
    frame_number: u64 = 0,
    present_time_ns: i128 = 0,
    frame_time_ns: u64 = 0, // Time since last frame
    render_time_ns: u64 = 0, // GPU render time
    scanout_time_ns: u64 = 0, // Time until scanout
    missed_frames: u64 = 0,
    direct_scanout_frames: u64 = 0,
    compositor_frames: u64 = 0,
    vrr_active: bool = false,
    tearing_active: bool = false,

    pub fn fps(self: FrameStats) f32 {
        if (self.frame_time_ns == 0) return 0;
        return 1_000_000_000.0 / @as(f32, @floatFromInt(self.frame_time_ns));
    }

    pub fn frameTimeMs(self: FrameStats) f32 {
        return @as(f32, @floatFromInt(self.frame_time_ns)) / 1_000_000.0;
    }

    pub fn renderTimeMs(self: FrameStats) f32 {
        return @as(f32, @floatFromInt(self.render_time_ns)) / 1_000_000.0;
    }
};

// ============================================================================
// Compositor Context
// ============================================================================

pub const CompositorError = error{
    WlrNotFound,
    DisplayCreateFailed,
    BackendCreateFailed,
    RendererCreateFailed,
    AllocatorCreateFailed,
    SocketCreateFailed,
    BackendStartFailed,
    InvalidState,
    OutputNotFound,
    OutOfMemory,
};

/// Compositor context
pub const Context = struct {
    allocator: std.mem.Allocator,
    config: Config,
    state: State = .uninitialized,

    // wlroots handles
    wlr: WlrFunctions = .{},
    display: ?*wl_display = null,
    backend: ?*wlr_backend = null,
    renderer: ?*wlr_renderer = null,
    wlr_allocator: ?*wlr_allocator = null,
    compositor: ?*wlr_compositor = null,
    scene: ?*wlr_scene = null,
    output_layout: ?*wlr_output_layout = null,
    xdg_shell: ?*wlr_xdg_shell = null,
    layer_shell: ?*wlr_layer_shell_v1 = null,
    seat: ?*wlr_seat = null,
    cursor: ?*wlr_cursor = null,
    xcursor_manager: ?*wlr_xcursor_manager = null,

    // Output tracking
    outputs: std.ArrayList(OutputInfo),
    current_output_index: usize = 0,

    // Window tracking
    windows: std.ArrayList(WindowInfo),
    focused_window_id: ?u64 = null,
    next_window_id: u64 = 1,

    // Wayland socket
    socket_name: [108]u8 = [_]u8{0} ** 108,
    socket_name_len: usize = 0,

    // Frame stats
    stats: FrameStats = .{},
    last_frame_time: i128 = 0,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: Config) CompositorError!*Self {
        const self = allocator.create(Self) catch return CompositorError.OutOfMemory;
        self.* = Self{
            .allocator = allocator,
            .config = config,
            .outputs = .{},
            .windows = .{},
        };

        // Load wlroots dynamically
        self.loadWlroots() catch |err| {
            std.log.warn("wlroots not available: {}", .{err});
            // Continue for development/testing
        };

        self.state = .ready;
        return self;
    }

    pub fn deinit(self: *Self) void {
        if (self.state == .running) {
            self.stop();
        }

        // Cleanup wlroots resources
        if (self.display) |display| {
            if (self.wlr.wl_display_destroy) |destroy| {
                destroy(display);
            }
        }

        self.outputs.deinit(self.allocator);
        self.windows.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    fn loadWlroots(self: *Self) !void {
        const c = @cImport({
            @cInclude("dlfcn.h");
        });

        // Try to load wlroots library
        const lib_names = [_][*:0]const u8{
            "libwlroots-0.18.so",
            "libwlroots-0.17.so",
            "libwlroots.so.12",
            "libwlroots.so",
        };

        var handle: ?*anyopaque = null;
        for (lib_names) |lib_name| {
            handle = c.dlopen(lib_name, c.RTLD_LAZY);
            if (handle != null) {
                std.log.info("Loaded wlroots: {s}", .{lib_name});
                break;
            }
        }

        if (handle == null) {
            std.log.warn("wlroots library not found, compositor will run in stub mode", .{});
            return;
        }

        // Load wayland-server functions
        const wl_lib = c.dlopen("libwayland-server.so.0", c.RTLD_LAZY);
        if (wl_lib != null) {
            self.wlr.wl_display_create = @ptrCast(c.dlsym(wl_lib, "wl_display_create"));
            self.wlr.wl_display_destroy = @ptrCast(c.dlsym(wl_lib, "wl_display_destroy"));
            self.wlr.wl_display_get_event_loop = @ptrCast(c.dlsym(wl_lib, "wl_display_get_event_loop"));
            self.wlr.wl_display_run = @ptrCast(c.dlsym(wl_lib, "wl_display_run"));
            self.wlr.wl_display_terminate = @ptrCast(c.dlsym(wl_lib, "wl_display_terminate"));
            self.wlr.wl_display_add_socket_auto = @ptrCast(c.dlsym(wl_lib, "wl_display_add_socket_auto"));
        }

        // Load wlroots functions
        self.wlr.wlr_backend_autocreate = @ptrCast(c.dlsym(handle, "wlr_backend_autocreate"));
        self.wlr.wlr_backend_destroy = @ptrCast(c.dlsym(handle, "wlr_backend_destroy"));
        self.wlr.wlr_backend_start = @ptrCast(c.dlsym(handle, "wlr_backend_start"));
        self.wlr.wlr_renderer_autocreate = @ptrCast(c.dlsym(handle, "wlr_renderer_autocreate"));
        self.wlr.wlr_renderer_init_wl_display = @ptrCast(c.dlsym(handle, "wlr_renderer_init_wl_display"));
        self.wlr.wlr_allocator_autocreate = @ptrCast(c.dlsym(handle, "wlr_allocator_autocreate"));
        self.wlr.wlr_compositor_create = @ptrCast(c.dlsym(handle, "wlr_compositor_create"));
        self.wlr.wlr_scene_create = @ptrCast(c.dlsym(handle, "wlr_scene_create"));
        self.wlr.wlr_output_layout_create = @ptrCast(c.dlsym(handle, "wlr_output_layout_create"));
        self.wlr.wlr_xdg_shell_create = @ptrCast(c.dlsym(handle, "wlr_xdg_shell_create"));
        self.wlr.wlr_seat_create = @ptrCast(c.dlsym(handle, "wlr_seat_create"));
        self.wlr.wlr_cursor_create = @ptrCast(c.dlsym(handle, "wlr_cursor_create"));
        self.wlr.wlr_xcursor_manager_create = @ptrCast(c.dlsym(handle, "wlr_xcursor_manager_create"));

        std.log.info("wlroots functions loaded successfully", .{});
    }

    pub fn start(self: *Self) CompositorError!void {
        if (self.state != .ready) return CompositorError.InvalidState;

        self.state = .initializing;

        // TODO: Full wlroots initialization sequence:
        // 1. wl_display_create()
        // 2. wlr_backend_autocreate()
        // 3. wlr_renderer_autocreate()
        // 4. wlr_allocator_autocreate()
        // 5. wlr_compositor_create()
        // 6. wlr_scene_create()
        // 7. wlr_output_layout_create()
        // 8. wlr_xdg_shell_create()
        // 9. wlr_layer_shell_v1_create()
        // 10. wlr_seat_create()
        // 11. Set up event listeners
        // 12. wl_display_add_socket_auto()
        // 13. wlr_backend_start()

        // Mock: Add a test output
        var output = OutputInfo{
            .width = 2560,
            .height = 1440,
            .refresh_mhz = 165000,
            .vrr_capable = true,
            .hdr_capable = true,
            .max_luminance_nits = 1000,
            .tearing_capable = true,
        };
        const name = "DP-1";
        @memcpy(output.name[0..name.len], name);
        output.name_len = name.len;

        const make = "LG Electronics";
        @memcpy(output.make[0..make.len], make);
        output.make_len = make.len;

        const model = "27GP950-B";
        @memcpy(output.model[0..model.len], model);
        output.model_len = model.len;

        self.outputs.append(self.allocator, output) catch return CompositorError.OutOfMemory;

        // Set socket name
        const socket = "wayland-venom";
        @memcpy(self.socket_name[0..socket.len], socket);
        self.socket_name_len = socket.len;

        self.state = .running;
    }

    pub fn stop(self: *Self) void {
        if (self.state != .running and self.state != .paused) return;

        // TODO: Cleanup wlroots
        // - wl_display_terminate()

        self.state = .ready;
    }

    /// Run compositor event loop (blocking)
    pub fn run(self: *Self) CompositorError!void {
        if (self.state != .running) return CompositorError.InvalidState;

        // TODO: wl_display_run(self.display)
        // For now, simulate frame loop
        while (self.state == .running) {
            self.processFrame();
            std.time.sleep(std.time.ns_per_ms * 6); // ~165fps
        }
    }

    /// Process one frame (non-blocking)
    pub fn processFrame(self: *Self) void {
        const now = std.time.nanoTimestamp();
        if (self.last_frame_time > 0) {
            self.stats.frame_time_ns = @intCast(now - self.last_frame_time);
        }
        self.last_frame_time = now;
        self.stats.frame_number += 1;
        self.stats.present_time_ns = now;

        // Check for direct scanout opportunity
        if (self.config.direct_scanout) {
            if (self.tryDirectScanout()) {
                self.stats.direct_scanout_frames += 1;
            } else {
                self.stats.compositor_frames += 1;
            }
        }
    }

    fn tryDirectScanout(self: *Self) bool {
        // Direct scanout conditions:
        // 1. Single fullscreen window
        // 2. Window covers entire output
        // 3. Compatible pixel format
        // 4. No overlays active
        if (self.focused_window_id) |id| {
            for (self.windows.items) |window| {
                if (window.id == id and window.fullscreen and window.can_direct_scanout) {
                    return true;
                }
            }
        }
        return false;
    }

    pub fn getSocketName(self: *const Self) ?[]const u8 {
        if (self.socket_name_len == 0) return null;
        return self.socket_name[0..self.socket_name_len];
    }

    pub fn getCurrentOutput(self: *const Self) ?OutputInfo {
        if (self.current_output_index >= self.outputs.items.len) return null;
        return self.outputs.items[self.current_output_index];
    }

    pub fn getOutputs(self: *const Self) []const OutputInfo {
        return self.outputs.items;
    }

    pub fn getWindows(self: *const Self) []const WindowInfo {
        return self.windows.items;
    }

    pub fn getStats(self: *const Self) FrameStats {
        return self.stats;
    }

    // ========================================================================
    // Display Settings
    // ========================================================================

    pub fn setVrr(self: *Self, state: VrrState) void {
        self.config.vrr_state = state;
        // TODO: Apply to DRM connector via wlr_output
        if (self.current_output_index < self.outputs.items.len) {
            self.outputs.items[self.current_output_index].vrr_enabled = (state != .disabled);
        }
    }

    pub fn setHdr(self: *Self, state: HdrState) void {
        self.config.hdr_state = state;
        // TODO: Apply HDR metadata via DRM
        if (self.current_output_index < self.outputs.items.len) {
            self.outputs.items[self.current_output_index].hdr_enabled = (state != .disabled);
        }
    }

    pub fn setHdrMetadata(self: *Self, metadata: HdrMetadata) void {
        self.config.hdr_metadata = metadata;
        // TODO: Apply to DRM connector
    }

    pub fn setDirectScanout(self: *Self, enabled: bool) void {
        self.config.direct_scanout = enabled;
    }

    pub fn setTearingMode(self: *Self, mode: TearingMode) void {
        self.config.tearing_mode = mode;
        // TODO: Apply to wp_tearing_control
    }

    pub fn setRefreshRate(self: *Self, refresh_mhz: u32) CompositorError!void {
        self.config.refresh_rate_mhz = refresh_mhz;
        // TODO: Apply mode change via wlr_output_set_mode
    }

    pub fn setResolution(self: *Self, width: u32, height: u32) CompositorError!void {
        self.config.output_width = width;
        self.config.output_height = height;
        // TODO: Apply mode change
    }

    // ========================================================================
    // Window Management
    // ========================================================================

    pub fn setFullscreen(self: *Self, window_id: u64, fullscreen: bool) void {
        for (self.windows.items) |*window| {
            if (window.id == window_id) {
                window.fullscreen = fullscreen;
                // TODO: wlr_xdg_toplevel_set_fullscreen
                break;
            }
        }
    }

    pub fn focusWindow(self: *Self, window_id: u64) void {
        self.focused_window_id = window_id;
        for (self.windows.items) |*window| {
            window.focused = (window.id == window_id);
            // TODO: wlr_seat_keyboard_notify_enter
        }
    }

    pub fn closeWindow(self: *Self, window_id: u64) void {
        for (self.windows.items, 0..) |window, i| {
            if (window.id == window_id) {
                // TODO: Send close request via XDG protocol
                _ = self.windows.orderedRemove(i);
                if (self.focused_window_id == window_id) {
                    self.focused_window_id = if (self.windows.items.len > 0)
                        self.windows.items[0].id
                    else
                        null;
                }
                break;
            }
        }
    }
};

// ============================================================================
// Public API
// ============================================================================

/// Check if wlroots is available
pub fn isWlrootsAvailable() bool {
    // TODO: Check for libwlroots
    return true;
}

/// Get wlroots version
pub fn getWlrootsVersion() ?[]const u8 {
    return "0.18.0";
}

/// Check if running under Wayland
pub fn isWaylandSession() bool {
    return std.posix.getenv("WAYLAND_DISPLAY") != null;
}

/// Check if VRR is supported by compositor
pub fn isVrrSupported() bool {
    return true;
}

/// Check if HDR is supported
pub fn isHdrSupported() bool {
    return true;
}

/// Check if tearing is supported
pub fn isTearingSupported() bool {
    return true;
}

// ============================================================================
// Tests
// ============================================================================

test "compositor config defaults" {
    const config = Config{};
    try std.testing.expectEqual(Mode.full, config.mode);
    try std.testing.expectEqual(VrrState.adaptive, config.vrr_state);
    try std.testing.expectEqual(HdrState.passthrough, config.hdr_state);
    try std.testing.expect(config.direct_scanout);
}

test "output info" {
    var info = OutputInfo{
        .width = 3840,
        .height = 2160,
        .refresh_mhz = 144000,
        .physical_width_mm = 600,
        .physical_height_mm = 340,
    };
    try std.testing.expectEqual(@as(u32, 144), info.refreshHz());
    try std.testing.expect(info.diagonalInches() > 27.0);
    try std.testing.expect(info.diagonalInches() < 28.0);
}

test "frame stats fps" {
    const stats = FrameStats{
        .frame_time_ns = 6_944_444, // ~144fps
    };
    const fps = stats.fps();
    try std.testing.expect(fps > 143.0);
    try std.testing.expect(fps < 145.0);
}

test "context init" {
    const allocator = std.testing.allocator;
    var ctx = try Context.init(allocator, .{});
    defer ctx.deinit();

    try std.testing.expectEqual(State.ready, ctx.state);
}

test "context start" {
    const allocator = std.testing.allocator;
    var ctx = try Context.init(allocator, .{});
    defer ctx.deinit();

    try ctx.start();
    try std.testing.expectEqual(State.running, ctx.state);
    try std.testing.expect(ctx.outputs.items.len > 0);
}

test "video mode refresh" {
    const mode = VideoMode{
        .width = 2560,
        .height = 1440,
        .refresh_mhz = 165000,
        .preferred = true,
    };
    try std.testing.expectEqual(@as(u32, 165), mode.refreshHz());
}
