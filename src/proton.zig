//! VENOM Proton/Steam Integration
//!
//! Launches games through Steam/Proton with optimal NVIDIA settings.
//! Handles environment variable injection, Proton selection, and
//! game-specific configurations.
//!
//! Integration with NVPrime:
//! - nvproton: Proton detection and launch helpers
//! - nvdlss: DLSS configuration for Proton games
//! - nvlatency: Reflex markers for compatible games

const std = @import("std");
const nvprime = @import("nvprime");

const nvdlss = nvprime.nvdlss;

/// Proton version preference
pub const ProtonVersion = enum {
    /// System default (Steam's choice)
    system,
    /// Latest stable GE-Proton
    ge_latest,
    /// Proton Experimental
    experimental,
    /// Specific version (set via custom_version)
    custom,

    pub fn description(self: ProtonVersion) []const u8 {
        return switch (self) {
            .system => "System default",
            .ge_latest => "GE-Proton (latest)",
            .experimental => "Proton Experimental",
            .custom => "Custom version",
        };
    }
};

/// Steam runtime mode
pub const SteamRuntime = enum {
    /// Native Steam runtime
    native,
    /// Steam runtime container (pressure-vessel)
    container,
    /// Flatpak Steam
    flatpak,

    pub fn description(self: SteamRuntime) []const u8 {
        return switch (self) {
            .native => "Native",
            .container => "Container (pressure-vessel)",
            .flatpak => "Flatpak",
        };
    }
};

/// Proton launch configuration
pub const ProtonConfig = struct {
    /// Proton version to use
    version: ProtonVersion = .system,
    /// Custom Proton path (for .custom version)
    custom_path: ?[]const u8 = null,
    /// Enable DXVK async shader compilation
    dxvk_async: bool = true,
    /// Enable VKD3D-Proton for DX12 games
    vkd3d_enabled: bool = true,
    /// Enable FSR (FidelityFX Super Resolution)
    fsr_enabled: bool = false,
    /// FSR sharpness (0-5, higher = sharper)
    fsr_sharpness: u8 = 2,
    /// Enable gamemode integration
    gamemode: bool = true,
    /// Enable MangoHud (disabled if VENOM HUD active)
    mangohud: bool = false,
    /// DLSS preset for DLSS-compatible games
    dlss_preset: ?nvdlss.DlssPreset = null,
    /// Enable Reflex for compatible games
    reflex_enabled: bool = true,
    /// Custom environment variables
    custom_env: ?std.StringHashMap([]const u8) = null,
};

/// Steam game info
pub const SteamGame = struct {
    app_id: u32,
    name: [256]u8 = [_]u8{0} ** 256,
    name_len: usize = 0,
    install_path: [512]u8 = [_]u8{0} ** 512,
    install_path_len: usize = 0,
    is_proton: bool = false,
    proton_prefix: [512]u8 = [_]u8{0} ** 512,
    proton_prefix_len: usize = 0,

    pub fn getName(self: *const SteamGame) []const u8 {
        return self.name[0..self.name_len];
    }

    pub fn getInstallPath(self: *const SteamGame) []const u8 {
        return self.install_path[0..self.install_path_len];
    }

    pub fn getProtonPrefix(self: *const SteamGame) []const u8 {
        return self.proton_prefix[0..self.proton_prefix_len];
    }
};

/// Steam/Proton launcher context
pub const Launcher = struct {
    allocator: std.mem.Allocator,
    config: ProtonConfig,

    // Steam paths
    steam_root: [512]u8 = [_]u8{0} ** 512,
    steam_root_len: usize = 0,
    compatdata_path: [512]u8 = [_]u8{0} ** 512,
    compatdata_path_len: usize = 0,

    // Detected runtime
    runtime: SteamRuntime = .native,

    // Current game
    current_game: ?SteamGame = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: ProtonConfig) !*Self {
        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .config = config,
        };

        // Detect Steam installation
        self.detectSteam();

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }

    /// Detect Steam installation path and runtime
    fn detectSteam(self: *Self) void {
        // Check common Steam paths
        const steam_paths = [_][]const u8{
            "~/.steam/steam",
            "~/.local/share/Steam",
            "/var/lib/flatpak/app/com.valvesoftware.Steam",
        };

        const home = std.posix.getenv("HOME") orelse "/home";

        for (steam_paths) |path| {
            var full_path_buf: [512]u8 = undefined;
            const full_path = if (path[0] == '~')
                std.fmt.bufPrint(&full_path_buf, "{s}{s}", .{ home, path[1..] }) catch continue
            else
                path;

            if (std.fs.cwd().access(full_path, .{})) |_| {
                const len = @min(full_path.len, self.steam_root.len);
                @memcpy(self.steam_root[0..len], full_path[0..len]);
                self.steam_root_len = len;

                // Detect runtime type
                if (std.mem.indexOf(u8, path, "flatpak") != null) {
                    self.runtime = .flatpak;
                } else {
                    self.runtime = .native;
                }

                // Set compatdata path
                const compat = std.fmt.bufPrint(&self.compatdata_path, "{s}/steamapps/compatdata", .{full_path}) catch continue;
                self.compatdata_path_len = compat.len;

                std.log.info("Steam detected at: {s} (runtime: {s})", .{
                    full_path,
                    self.runtime.description(),
                });
                break;
            } else |_| {}
        }
    }

    /// Build environment variables for launching a game
    pub fn buildEnvironment(self: *Self, allocator: std.mem.Allocator) !std.process.EnvMap {
        var env = try std.process.getEnvMap(allocator);

        // NVIDIA gaming optimizations
        try env.put("__GL_GSYNC_ALLOWED", "1");
        try env.put("__GL_VRR_ALLOWED", "1");
        try env.put("__GL_SHADER_DISK_CACHE", "1");
        try env.put("__GL_SHADER_DISK_CACHE_SKIP_CLEANUP", "1");

        // Low latency settings
        try env.put("__GL_MaxFramesAllowed", "1");
        try env.put("DXVK_ASYNC", if (self.config.dxvk_async) "1" else "0");

        // VKD3D-Proton for DX12
        if (self.config.vkd3d_enabled) {
            try env.put("VKD3D_FEATURE_LEVEL", "12_2");
        }

        // FSR
        if (self.config.fsr_enabled) {
            try env.put("WINE_FULLSCREEN_FSR", "1");
            var sharpness_buf: [8]u8 = undefined;
            const sharpness = std.fmt.bufPrint(&sharpness_buf, "{d}", .{self.config.fsr_sharpness}) catch "2";
            try env.put("WINE_FULLSCREEN_FSR_STRENGTH", sharpness);
        }

        // Gamemode
        if (self.config.gamemode) {
            try env.put("GAMEMODERUNEXEC", "1");
        }

        // MangoHud (disabled by default when using VENOM)
        if (self.config.mangohud) {
            try env.put("MANGOHUD", "1");
        } else {
            try env.put("DISABLE_MANGOHUD", "1");
        }

        // DLSS configuration
        if (self.config.dlss_preset) |preset| {
            const dlss_config = nvdlss.DlssConfig.fromPreset(preset);
            try env.put("DXVK_ENABLE_NVAPI", "1");
            try env.put("PROTON_ENABLE_NVAPI", "1");

            // Set DLSS quality mode
            var quality_buf: [8]u8 = undefined;
            const quality = std.fmt.bufPrint(&quality_buf, "{d}", .{@intFromEnum(dlss_config.quality_mode)}) catch "2";
            try env.put("DLSS_QUALITY", quality);
        }

        // Reflex
        if (self.config.reflex_enabled) {
            try env.put("DXVK_NVAPI_ALLOW_OTHER_DRIVERS", "1");
            try env.put("VKD3D_CONFIG", "dxr11,dxr");
        }

        // Custom environment variables
        if (self.config.custom_env) |custom| {
            var iter = custom.iterator();
            while (iter.next()) |entry| {
                try env.put(entry.key_ptr.*, entry.value_ptr.*);
            }
        }

        // Mark as VENOM-launched
        try env.put("VENOM_ENABLED", "1");

        return env;
    }

    /// Launch a Steam game by App ID
    pub fn launchSteamGame(self: *Self, app_id: u32) !std.process.Child {
        var env = try self.buildEnvironment(self.allocator);
        defer env.deinit();

        // Build Steam launch command
        var url_buf: [64]u8 = undefined;
        const steam_url = try std.fmt.bufPrint(&url_buf, "steam://rungameid/{d}", .{app_id});

        const argv = switch (self.runtime) {
            .native => &[_][]const u8{ "steam", steam_url },
            .container => &[_][]const u8{ "steam", steam_url },
            .flatpak => &[_][]const u8{ "flatpak", "run", "com.valvesoftware.Steam", steam_url },
        };

        var child = std.process.Child.init(argv, self.allocator);
        child.env_map = &env;

        try child.spawn();

        std.log.info("Launched Steam game {d} via {s}", .{ app_id, self.runtime.description() });

        return child;
    }

    /// Launch a game executable directly with Proton
    pub fn launchWithProton(self: *Self, exe_path: []const u8, args: ?[]const []const u8) !std.process.Child {
        var env = try self.buildEnvironment(self.allocator);
        defer env.deinit();

        // Get Proton path
        const proton_path = try self.getProtonPath();

        // Build argv
        var argv_list = std.ArrayList([]const u8).init(self.allocator);
        defer argv_list.deinit();

        try argv_list.append(proton_path);
        try argv_list.append("run");
        try argv_list.append(exe_path);

        if (args) |extra_args| {
            for (extra_args) |arg| {
                try argv_list.append(arg);
            }
        }

        var child = std.process.Child.init(argv_list.items, self.allocator);
        child.env_map = &env;

        try child.spawn();

        std.log.info("Launched {s} with Proton", .{exe_path});

        return child;
    }

    /// Get Proton executable path
    fn getProtonPath(self: *Self) ![]const u8 {
        _ = self;
        // TODO: Implement Proton version detection
        // For now, return a placeholder
        return "proton";
    }

    /// Get Steam library folders
    pub fn getLibraryFolders(self: *Self, allocator: std.mem.Allocator) ![][]const u8 {
        var folders = std.ArrayList([]const u8).init(allocator);

        // Main Steam library
        if (self.steam_root_len > 0) {
            var path_buf: [512]u8 = undefined;
            const path = try std.fmt.bufPrint(&path_buf, "{s}/steamapps", .{self.steam_root[0..self.steam_root_len]});
            try folders.append(try allocator.dupe(u8, path));
        }

        // TODO: Parse libraryfolders.vdf for additional libraries

        return folders.items;
    }
};

/// Check if Steam is running
pub fn isSteamRunning() bool {
    const result = std.process.Child.run(.{
        .allocator = std.heap.page_allocator,
        .argv = &.{ "pgrep", "-x", "steam" },
    }) catch return false;
    defer std.heap.page_allocator.free(result.stdout);
    defer std.heap.page_allocator.free(result.stderr);

    return result.term.Exited == 0;
}

/// Get Steam user ID
pub fn getSteamUserId() ?u64 {
    // Read from ~/.steam/steam/config/loginusers.vdf
    // For now, return null
    return null;
}

// ============================================================================
// Tests
// ============================================================================

test "proton config defaults" {
    const config = ProtonConfig{};
    try std.testing.expect(config.dxvk_async);
    try std.testing.expect(config.vkd3d_enabled);
    try std.testing.expect(!config.mangohud);
}

test "proton version description" {
    const version = ProtonVersion.ge_latest;
    try std.testing.expectEqualStrings("GE-Proton (latest)", version.description());
}
