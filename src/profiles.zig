//! VENOM Game Profiles
//!
//! Per-game configuration for DLSS, latency, VRR, HDR, and other settings.
//! Profiles can be auto-detected or manually configured.
//!
//! Features:
//! - Per-game DLSS presets
//! - Per-game latency modes
//! - VRR/G-Sync configuration
//! - HDR/Auto-HDR settings
//! - Custom environment variables

const std = @import("std");
const nvprime = @import("nvprime");

const nvdlss = nvprime.nvdlss;

/// Game profile
pub const Profile = struct {
    /// Game identifier (Steam AppID, executable name, or custom)
    id: [64]u8 = [_]u8{0} ** 64,
    id_len: usize = 0,

    /// Display name
    name: [128]u8 = [_]u8{0} ** 128,
    name_len: usize = 0,

    // DLSS settings
    dlss_enabled: bool = false,
    dlss_preset: nvdlss.DlssPreset = .default,
    dlss_quality: nvdlss.QualityMode = .balanced,
    frame_gen_enabled: bool = false,
    frame_gen_mode: nvdlss.FrameGenMode = .disabled,
    ray_reconstruction: bool = false,

    // Latency settings
    low_latency: bool = true,
    reflex_mode: enum { off, on, boost } = .on,
    max_frame_queue: u8 = 2,

    // VRR settings
    vrr_enabled: bool = true,
    fps_limit: u32 = 0, // 0 = unlimited

    // HDR settings
    hdr_enabled: bool = true,
    auto_hdr: bool = false,
    auto_hdr_preset: enum { standard, vivid, accurate, cinema } = .standard,
    sdr_brightness_nits: u32 = 203,
    hdr_peak_nits: u32 = 1000,

    // Compositor settings
    direct_scanout: bool = true,
    tearing_allowed: bool = false,

    // Custom environment variables
    env_count: usize = 0,
    env_keys: [16][64]u8 = undefined,
    env_values: [16][128]u8 = undefined,
    env_key_lens: [16]usize = [_]usize{0} ** 16,
    env_value_lens: [16]usize = [_]usize{0} ** 16,

    pub fn getId(self: *const Profile) []const u8 {
        return self.id[0..self.id_len];
    }

    pub fn getName(self: *const Profile) []const u8 {
        return self.name[0..self.name_len];
    }

    pub fn setId(self: *Profile, id_str: []const u8) void {
        const len = @min(id_str.len, self.id.len);
        @memcpy(self.id[0..len], id_str[0..len]);
        self.id_len = len;
    }

    pub fn setName(self: *Profile, name_str: []const u8) void {
        const len = @min(name_str.len, self.name.len);
        @memcpy(self.name[0..len], name_str[0..len]);
        self.name_len = len;
    }

    /// Add custom environment variable
    pub fn addEnv(self: *Profile, key: []const u8, value: []const u8) !void {
        if (self.env_count >= 16) return error.EnvFull;

        const key_len = @min(key.len, 64);
        const value_len = @min(value.len, 128);

        @memcpy(self.env_keys[self.env_count][0..key_len], key[0..key_len]);
        @memcpy(self.env_values[self.env_count][0..value_len], value[0..value_len]);
        self.env_key_lens[self.env_count] = key_len;
        self.env_value_lens[self.env_count] = value_len;
        self.env_count += 1;
    }

    /// Apply profile to environment
    pub fn applyToEnv(self: *const Profile, env: *std.process.EnvMap) !void {
        // DLSS settings
        if (self.dlss_enabled) {
            try env.put("DXVK_ENABLE_NVAPI", "1");
            try env.put("PROTON_ENABLE_NVAPI", "1");
        }

        // Low latency
        if (self.low_latency) {
            try env.put("__GL_MaxFramesAllowed", "1");
            switch (self.reflex_mode) {
                .off => {},
                .on => try env.put("DXVK_NVAPI_ALLOW_OTHER_DRIVERS", "1"),
                .boost => {
                    try env.put("DXVK_NVAPI_ALLOW_OTHER_DRIVERS", "1");
                    try env.put("__GL_SYNC_TO_VBLANK", "0");
                },
            }
        }

        // FPS limit
        if (self.fps_limit > 0) {
            var buf: [16]u8 = undefined;
            const fps_str = std.fmt.bufPrint(&buf, "{d}", .{self.fps_limit}) catch "0";
            try env.put("__GL_SYNC_DISPLAY_DEVICE", fps_str);
        }

        // VRR
        if (self.vrr_enabled) {
            try env.put("__GL_GSYNC_ALLOWED", "1");
            try env.put("__GL_VRR_ALLOWED", "1");
        }

        // Tearing
        if (self.tearing_allowed) {
            try env.put("__GL_SYNC_TO_VBLANK", "0");
        }

        // Custom environment variables
        for (0..self.env_count) |i| {
            const key = self.env_keys[i][0..self.env_key_lens[i]];
            const value = self.env_values[i][0..self.env_value_lens[i]];
            try env.put(key, value);
        }
    }

    /// Create default profile
    pub fn default() Profile {
        return Profile{};
    }

    /// Create low latency profile (competitive gaming)
    pub fn lowLatency() Profile {
        var p = Profile{};
        p.setName("Low Latency");
        p.low_latency = true;
        p.reflex_mode = .boost;
        p.max_frame_queue = 1;
        p.vrr_enabled = true;
        p.tearing_allowed = true;
        p.direct_scanout = true;
        return p;
    }

    /// Create quality profile (single player, visual fidelity)
    pub fn quality() Profile {
        var p = Profile{};
        p.setName("Quality");
        p.dlss_enabled = true;
        p.dlss_preset = .preset_c; // Quality focused
        p.dlss_quality = .quality;
        p.low_latency = false;
        p.reflex_mode = .off;
        p.hdr_enabled = true;
        p.tearing_allowed = false;
        return p;
    }

    /// Create balanced profile
    pub fn balanced() Profile {
        var p = Profile{};
        p.setName("Balanced");
        p.dlss_enabled = true;
        p.dlss_preset = .preset_a; // Higher quality, temporal stability
        p.frame_gen_enabled = true;
        p.frame_gen_mode = .enabled;
        p.low_latency = true;
        p.reflex_mode = .on;
        p.vrr_enabled = true;
        return p;
    }

    /// Create max FPS profile
    pub fn maxFps() Profile {
        var p = Profile{};
        p.setName("Max FPS");
        p.dlss_enabled = true;
        p.dlss_preset = .preset_d; // Performance focused
        p.dlss_quality = .ultra_performance;
        p.frame_gen_enabled = true;
        p.frame_gen_mode = .dynamic;
        p.low_latency = true;
        p.reflex_mode = .boost;
        p.vrr_enabled = true;
        p.tearing_allowed = true;
        return p;
    }
};

/// Profile manager
pub const ProfileManager = struct {
    allocator: std.mem.Allocator,
    profiles: std.StringHashMap(Profile),
    default_profile: Profile,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .profiles = std.StringHashMap(Profile).init(allocator),
            .default_profile = Profile.default(),
        };
    }

    pub fn deinit(self: *Self) void {
        self.profiles.deinit();
    }

    /// Add or update a profile
    pub fn addProfile(self: *Self, profile: Profile) !void {
        const id = profile.getId();
        const key = try self.allocator.dupe(u8, id);
        try self.profiles.put(key, profile);
    }

    /// Get profile for a game
    pub fn getProfile(self: *const Self, game_id: []const u8) ?Profile {
        return self.profiles.get(game_id);
    }

    /// Get profile or default
    pub fn getProfileOrDefault(self: *const Self, game_id: []const u8) Profile {
        return self.profiles.get(game_id) orelse self.default_profile;
    }

    /// Remove a profile
    pub fn removeProfile(self: *Self, game_id: []const u8) void {
        _ = self.profiles.remove(game_id);
    }

    /// Set default profile
    pub fn setDefaultProfile(self: *Self, profile: Profile) void {
        self.default_profile = profile;
    }

    /// Load profiles from config directory
    pub fn loadProfiles(self: *Self, config_dir: []const u8) !void {
        _ = self;
        _ = config_dir;
        // TODO: Load from TOML files in config_dir/profiles/
    }

    /// Save profiles to config directory
    pub fn saveProfiles(self: *const Self, config_dir: []const u8) !void {
        _ = self;
        _ = config_dir;
        // TODO: Save to TOML files in config_dir/profiles/
    }
};

/// Auto-detect game and return appropriate profile
pub fn detectGameProfile(executable: []const u8) ?Profile {
    // Common game patterns and their optimal profiles

    // Competitive/esports games - low latency
    const competitive_games = [_][]const u8{
        "csgo",
        "cs2",
        "valorant",
        "apex",
        "fortnite",
        "overwatch",
        "r6",
        "pubg",
    };

    for (competitive_games) |game| {
        if (std.mem.indexOf(u8, executable, game) != null) {
            var profile = Profile.lowLatency();
            profile.setId(executable);
            return profile;
        }
    }

    // AAA single player - quality
    const quality_games = [_][]const u8{
        "cyberpunk",
        "rdr2",
        "witcher",
        "horizon",
        "godofwar",
        "spiderman",
    };

    for (quality_games) |game| {
        if (std.mem.indexOf(u8, executable, game) != null) {
            var profile = Profile.quality();
            profile.setId(executable);
            return profile;
        }
    }

    return null;
}

// ============================================================================
// Tests
// ============================================================================

test "profile defaults" {
    const profile = Profile.default();
    try std.testing.expect(profile.low_latency);
    try std.testing.expect(profile.vrr_enabled);
}

test "profile presets" {
    const low_lat = Profile.lowLatency();
    try std.testing.expect(low_lat.tearing_allowed);
    try std.testing.expectEqual(@as(u8, 1), low_lat.max_frame_queue);

    const quality = Profile.quality();
    try std.testing.expect(!quality.tearing_allowed);
    try std.testing.expect(quality.dlss_enabled);
}

test "profile manager" {
    const allocator = std.testing.allocator;
    var manager = ProfileManager.init(allocator);
    defer manager.deinit();

    var profile = Profile.lowLatency();
    profile.setId("test_game");
    try manager.addProfile(profile);

    const retrieved = manager.getProfile("test_game");
    try std.testing.expect(retrieved != null);
}
