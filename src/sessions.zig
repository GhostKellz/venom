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
    child: ?std.process.Child = null,
    running: bool = false,

    pub fn init(allocator: std.mem.Allocator) GamescopeSession {
        return GamescopeSession{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *GamescopeSession) void {
        if (self.child) |*child| {
            _ = child.kill() catch null;
        }
        self.child = null;
        self.running = false;
    }

    pub fn isRunning(self: *const GamescopeSession) bool {
        if (self.child) |child| {
            return child.id != 0;
        }
        return false;
    }

    pub fn start(self: *GamescopeSession, argv: []const []const u8) !void {
        if (self.isRunning()) return;

        var child = std.process.Child.init(argv, self.allocator);
        try child.spawn();
        self.child = child;
        self.running = true;
    }

    pub fn wait(self: *GamescopeSession) !void {
        if (self.child) |*child| {
            _ = try child.wait();
            self.running = false;
            self.child = null;
        }
    }

    pub fn stop(self: *GamescopeSession) void {
        if (self.child) |*child| {
            _ = child.kill() catch null;
            self.child = null;
        }
        self.running = false;
    }
};

pub fn isGamescopePresent() bool {
    std.fs.accessAbsolute("/usr/bin/gamescope", .{}) catch {
        return false;
    };
    return true;
}

pub fn getGamescopeBinary() []const u8 {
    if (std.posix.getenv("GAMESCOPE_BINARY")) |value| {
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
    if (std.posix.getenv("GAMESCOPE_WAYLAND_DISPLAY") != null or std.posix.getenv("GAMESCOPE_SESSION_ID") != null) {
        return .gamescope;
    }
    if (std.posix.getenv("WAYLAND_DISPLAY") != null) {
        // Default assumption: wlroots-based compositor if wlroots available
        if (@hasDecl(@import("compositor.zig"), "getWlrootsStatus")) {
            const status = @import("compositor.zig").getWlrootsStatus();
            if (status.available) return .wlroots;
        }
    }
    return .none;
}
