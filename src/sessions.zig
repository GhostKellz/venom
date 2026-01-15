//! Session helpers for compositor interop (Gamescope, wlroots nesting, etc.)
//! Provides detection and launch helpers for Gamescope-based shells.

const std = @import("std");

/// Gamescope session mode (Steam Deck vs Desktop)
pub const GamescopeMode = enum {
    /// Desktop mode - windowed Gamescope
    desktop,
    /// Steam Deck session - embedded/fullscreen mode
    steam_deck,
    /// Nested mode - inside existing Wayland session
    nested,

    pub fn description(self: GamescopeMode) []const u8 {
        return switch (self) {
            .desktop => "Desktop windowed mode",
            .steam_deck => "Steam Deck embedded session",
            .nested => "Nested inside existing Wayland compositor",
        };
    }
};

pub const GamescopeOptions = struct {
    /// Session mode
    mode: GamescopeMode = .desktop,
    /// Optional width for nested sessions
    width: ?u32 = null,
    /// Optional height for nested sessions
    height: ?u32 = null,
    /// Target refresh rate for Gamescope (Hz)
    refresh_hz: ?u32 = null,
    /// Enable HDR flag when launching Gamescope
    hdr: bool = false,
    /// Enable VRR when supported
    vrr: bool = true,
    /// Enable fullscreen mode
    fullscreen: bool = false,
    /// Borderless fullscreen
    borderless: bool = false,
    /// Force grab input
    force_grab: bool = false,
    /// Enable FSR upscaling (AMD FidelityFX)
    fsr: bool = false,
    /// FSR sharpness (0-20, default 5)
    fsr_sharpness: ?u8 = null,
    /// Enable NIS upscaling (NVIDIA Image Scaling)
    nis: bool = false,
    /// NIS sharpness (0-20, default 5)
    nis_sharpness: ?u8 = null,
    /// Enable MangoHud overlay
    mangohud: bool = false,
    /// Frame limit (0 = unlimited)
    fps_limit: u32 = 0,
    /// Expose Wayland to game (vs X11 only)
    expose_wayland: bool = false,
    /// Additional user-provided flags
    extra_flags: []const []const u8 = &.{},
    // Auto-HDR (RTX HDR for SDR games)
    /// Enable Auto-HDR (SDR to HDR conversion)
    auto_hdr: bool = false,
    /// SDR content brightness in nits (default 203)
    sdr_content_nits: ?u32 = null,
    /// Peak HDR brightness target in nits (default 1000)
    hdr_peak_nits: ?u32 = null,
    /// Enable wide gamut (BT.2020) for SDR content
    hdr_wide_gamut: bool = true,
};

pub const GamescopeCommand = struct {
    args: []const []const u8 = &.{},
    owned_buffers: []const []const u8 = &.{},

    pub fn deinit(self: *GamescopeCommand, allocator: std.mem.Allocator) void {
        if (self.args.len > 0) allocator.free(self.args);
        for (self.owned_buffers) |buf| allocator.free(buf);
        if (self.owned_buffers.len > 0) allocator.free(self.owned_buffers);
    }
};

pub const GamescopeSession = struct {
    allocator: std.mem.Allocator,
    pid: ?std.posix.pid_t = null,
    running: bool = false,

    pub fn init(allocator: std.mem.Allocator) GamescopeSession {
        return GamescopeSession{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *GamescopeSession) void {
        self.stop();
    }

    pub fn isRunning(self: *const GamescopeSession) bool {
        if (self.pid) |pid| {
            // Check if process is still alive using raw syscall
            // kill syscall: syscall(__NR_kill, pid, sig)
            const result = std.os.linux.syscall2(.kill, @as(usize, @bitCast(@as(isize, pid))), 0);
            const errno: isize = @bitCast(result);
            return errno == 0 or errno != -3; // -ESRCH = -3
        }
        return false;
    }

    pub fn start(self: *GamescopeSession, argv: []const []const u8) !void {
        if (self.isRunning()) return;
        if (argv.len == 0) return error.InvalidArgument;

        // Convert argv to C format for execve - use sentinel-terminated array
        var argv_buf: [257:null]?[*:0]const u8 = @splat(null);
        for (argv, 0..) |arg, i| {
            if (i >= 256) break;
            // Copy to null-terminated buffer
            const arg_z = self.allocator.dupeZ(u8, arg) catch return error.OutOfMemory;
            argv_buf[i] = arg_z;
        }

        const pid = std.c.fork();
        if (pid < 0) return error.ForkFailed;

        if (pid == 0) {
            // Child process - exec the command
            _ = std.c.execve(argv_buf[0].?, &argv_buf, std.c.environ);
            std.c._exit(127); // exec failed
        }

        // Parent process
        self.pid = pid;
        self.running = true;
    }

    pub fn wait(self: *GamescopeSession) !void {
        if (self.pid) |pid| {
            // Use C waitpid
            var status: c_int = 0;
            _ = std.c.waitpid(pid, &status, 0);
            self.running = false;
            self.pid = null;
        }
    }

    pub fn stop(self: *GamescopeSession) void {
        if (self.pid) |pid| {
            _ = std.os.linux.syscall2(.kill, @as(usize, @bitCast(@as(isize, pid))), 15); // SIGTERM = 15
            self.pid = null;
        }
        self.running = false;
    }
};

pub fn isGamescopePresent() bool {
    const result = std.c.access("/usr/bin/gamescope", 0); // F_OK = 0
    return result == 0;
}

pub fn getGamescopeBinary() []const u8 {
    if (std.c.getenv("GAMESCOPE_BINARY")) |value| {
        return std.mem.sliceTo(value, 0);
    }
    return "/usr/bin/gamescope";
}

fn appendIntArg(allocator: std.mem.Allocator, list: *std.ArrayListUnmanaged([]const u8), flag: []const u8, value: u32) !void {
    try list.append(allocator, flag);
    try list.append(allocator, try std.fmt.allocPrint(allocator, "{d}", .{value}));
}

pub fn buildGamescopeCommand(allocator: std.mem.Allocator, options: GamescopeOptions, game_cmd: []const []const u8) !GamescopeCommand {
    var args: std.ArrayListUnmanaged([]const u8) = .empty;
    defer args.deinit(allocator);
    var owned_buffers: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer owned_buffers.deinit(allocator);

    try args.append(allocator, getGamescopeBinary());

    // Session mode specific flags
    switch (options.mode) {
        .steam_deck => {
            try args.append(allocator, "--steam");
            try args.append(allocator, "-e"); // Embedded mode
        },
        .nested => {
            try args.append(allocator, "--nested-refresh-rate-hack");
        },
        .desktop => {},
    }

    // Resolution
    if (options.width) |w| {
        const val = try std.fmt.allocPrint(allocator, "{d}", .{w});
        try owned_buffers.append(allocator, val);
        try args.append(allocator, "-w");
        try args.append(allocator, val);
    }
    if (options.height) |h| {
        const val = try std.fmt.allocPrint(allocator, "{d}", .{h});
        try owned_buffers.append(allocator, val);
        try args.append(allocator, "-h");
        try args.append(allocator, val);
    }
    if (options.refresh_hz) |hz| {
        const val = try std.fmt.allocPrint(allocator, "{d}", .{hz});
        try owned_buffers.append(allocator, val);
        try args.append(allocator, "-r");
        try args.append(allocator, val);
    }

    // Display modes
    if (options.fullscreen) {
        try args.append(allocator, "-f");
    }
    if (options.borderless) {
        try args.append(allocator, "-b");
    }
    if (options.force_grab) {
        try args.append(allocator, "--force-grab-cursor");
    }

    // VRR and HDR
    if (options.hdr) {
        try args.append(allocator, "--hdr-enabled");
    }
    if (options.vrr) {
        try args.append(allocator, "--adaptive-sync");
    }

    // Auto-HDR (SDR to HDR conversion via Gamescope ITM)
    if (options.auto_hdr) {
        // Enable HDR if not already enabled
        if (!options.hdr) {
            try args.append(allocator, "--hdr-enabled");
        }
        // SDR content brightness
        const sdr_nits = options.sdr_content_nits orelse 203;
        const sdr_val = try std.fmt.allocPrint(allocator, "{d}", .{sdr_nits});
        try owned_buffers.append(allocator, sdr_val);
        try args.append(allocator, "--hdr-sdr-content-nits");
        try args.append(allocator, sdr_val);
        // Enable Inverse Tone Mapping for SDR-to-HDR
        try args.append(allocator, "--hdr-itm-enable");
        // Peak brightness target
        const peak_nits = options.hdr_peak_nits orelse 1000;
        const peak_val = try std.fmt.allocPrint(allocator, "{d}", .{peak_nits});
        try owned_buffers.append(allocator, peak_val);
        try args.append(allocator, "--hdr-itm-target-nits");
        try args.append(allocator, peak_val);
        // Wide gamut for SDR content
        if (options.hdr_wide_gamut) {
            try args.append(allocator, "--hdr-wide-gammut-for-sdr");
        }
    }

    // Upscaling
    if (options.fsr) {
        try args.append(allocator, "--fsr-sharpness");
        const sharpness = options.fsr_sharpness orelse 5;
        const val = try std.fmt.allocPrint(allocator, "{d}", .{sharpness});
        try owned_buffers.append(allocator, val);
        try args.append(allocator, val);
    }
    if (options.nis) {
        try args.append(allocator, "--nis-sharpness");
        const sharpness = options.nis_sharpness orelse 5;
        const val = try std.fmt.allocPrint(allocator, "{d}", .{sharpness});
        try owned_buffers.append(allocator, val);
        try args.append(allocator, val);
    }

    // Frame limiter (only set if specified, otherwise Gamescope defaults to unlimited)
    if (options.fps_limit > 0) {
        try args.append(allocator, "--framerate-limit");
        const val = try std.fmt.allocPrint(allocator, "{d}", .{options.fps_limit});
        try owned_buffers.append(allocator, val);
        try args.append(allocator, val);
    }

    // MangoHud integration
    if (options.mangohud) {
        try args.append(allocator, "--mangoapp");
    }

    // Wayland exposure
    if (options.expose_wayland) {
        try args.append(allocator, "--expose-wayland");
    }

    // Extra user flags
    for (options.extra_flags) |flag| {
        try args.append(allocator, flag);
    }

    try args.append(allocator, "--");
    for (game_cmd) |segment| {
        try args.append(allocator, segment);
    }

    return GamescopeCommand{
        .args = try args.toOwnedSlice(allocator),
        .owned_buffers = try owned_buffers.toOwnedSlice(allocator),
    };
}

/// Detect if running on Steam Deck hardware
pub fn isSteamDeck() bool {
    // Check for Steam Deck specific markers
    if (std.posix.getenv("SteamDeck")) |_| return true;

    // Check DMI product name
    const dmi_path = "/sys/class/dmi/id/product_name";
    var file = std.fs.openFileAbsolute(dmi_path, .{}) catch return false;
    defer file.close();

    var buf: [64]u8 = undefined;
    const len = file.read(&buf) catch return false;
    const product = buf[0..len];

    return std.mem.startsWith(u8, product, "Jupiter") or // Steam Deck LCD
        std.mem.startsWith(u8, product, "Galileo"); // Steam Deck OLED
}

/// Get recommended Gamescope options for Steam Deck
pub fn getSteamDeckOptions() GamescopeOptions {
    return .{
        .mode = .steam_deck,
        .width = 1280,
        .height = 800,
        .refresh_hz = 90, // Steam Deck OLED max
        .hdr = true,
        .vrr = true,
        .fullscreen = true,
        .fsr = true,
        .fsr_sharpness = 5,
        .mangohud = true,
    };
}

/// Get recommended Gamescope options for desktop
pub fn getDesktopOptions(width: u32, height: u32, refresh_hz: u32) GamescopeOptions {
    return .{
        .mode = .desktop,
        .width = width,
        .height = height,
        .refresh_hz = refresh_hz,
        .hdr = true,
        .vrr = true,
        .borderless = true,
        .nis = true, // NVIDIA NIS for NVIDIA GPUs
        .nis_sharpness = 5,
    };
}

pub fn detectNestedSession() enum { none, gamescope, wlroots } {
    if (std.c.getenv("GAMESCOPE_WAYLAND_DISPLAY") != null or std.c.getenv("GAMESCOPE_SESSION_ID") != null) {
        return .gamescope;
    }
    if (std.c.getenv("WAYLAND_DISPLAY") != null) {
        // Default assumption: wlroots-based compositor if wlroots available
        if (@hasDecl(@import("compositor.zig"), "getWlrootsStatus")) {
            const status = @import("compositor.zig").getWlrootsStatus();
            if (status.available) return .wlroots;
        }
    }
    return .none;
}
