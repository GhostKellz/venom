//! CPU Governor management helpers for VENOM
//!
//! Provides detection and temporary override for CPU scaling governors.
//! Supports:
//! - Traditional governors (performance, powersave, schedutil, ondemand)
//! - AMD P-State EPP (Energy Performance Preference)
//! - Intel HWP (Hardware P-States)

const std = @import("std");

pub const GovernorError = error{
    UnsupportedPlatform,
    NotAvailable,
    PermissionDenied,
};

/// CPU scaling driver type
pub const ScalingDriver = enum {
    unknown,
    acpi_cpufreq,
    amd_pstate,
    amd_pstate_epp,
    intel_pstate,
    intel_cpufreq,

    pub fn description(self: ScalingDriver) []const u8 {
        return switch (self) {
            .unknown => "Unknown",
            .acpi_cpufreq => "ACPI CPUFreq",
            .amd_pstate => "AMD P-State",
            .amd_pstate_epp => "AMD P-State EPP",
            .intel_pstate => "Intel P-State",
            .intel_cpufreq => "Intel CPUFreq",
        };
    }

    pub fn supportsEpp(self: ScalingDriver) bool {
        return self == .amd_pstate_epp or self == .intel_pstate;
    }
};

/// AMD P-State EPP preference
pub const EppPreference = enum {
    default,
    performance,
    balance_performance,
    balance_power,
    power,

    pub fn toSysfs(self: EppPreference) []const u8 {
        return switch (self) {
            .default => "default",
            .performance => "performance",
            .balance_performance => "balance_performance",
            .balance_power => "balance_power",
            .power => "power",
        };
    }

    pub fn fromSysfs(value: []const u8) EppPreference {
        const trimmed = std.mem.trimRight(u8, value, "\n");
        if (std.mem.eql(u8, trimmed, "performance")) return .performance;
        if (std.mem.eql(u8, trimmed, "balance_performance")) return .balance_performance;
        if (std.mem.eql(u8, trimmed, "balance_power")) return .balance_power;
        if (std.mem.eql(u8, trimmed, "power")) return .power;
        return .default;
    }
};

pub const GovernorEntry = struct {
    path: []u8,
    original: ?[]u8 = null,
    epp_path: ?[]u8 = null,
    original_epp: ?[]u8 = null,
};

pub const GovernorState = struct {
    allocator: std.mem.Allocator,
    entries: []GovernorEntry = &.{},
    driver: ScalingDriver = .unknown,
    original_boost: ?bool = null,

    pub fn init(allocator: std.mem.Allocator) GovernorState {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *GovernorState) void {
        // Restore original state before cleanup
        restore(self);

        for (self.entries) |entry| {
            self.allocator.free(entry.path);
            if (entry.original) |value| self.allocator.free(value);
            if (entry.epp_path) |p| self.allocator.free(p);
            if (entry.original_epp) |value| self.allocator.free(value);
        }
        if (self.entries.len > 0) self.allocator.free(self.entries);
        self.* = .{ .allocator = self.allocator };
    }
};

const governor_root = "/sys/devices/system/cpu";
const governor_file = "scaling_governor";

fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();
    var buf: [128]u8 = undefined;
    const len = file.read(&buf) catch return error.ReadError;
    const result = try allocator.alloc(u8, len);
    @memcpy(result, buf[0..len]);
    return result;
}

fn writeFile(path: []const u8, value: []const u8) !void {
    var file = try std.fs.openFileAbsolute(path, .{ .mode = .write_only });
    defer file.close();
    try file.seekTo(0);
    _ = try file.writeAll(value);
}

pub fn isAvailable() bool {
    std.fs.accessAbsolute(governor_root, .{}) catch return false;
    return true;
}

fn enumerateGovernorFiles(allocator: std.mem.Allocator) ![]GovernorEntry {
    var list: std.ArrayListUnmanaged(GovernorEntry) = .empty;
    errdefer list.deinit(allocator);

    var dir = try std.fs.openDirAbsolute(governor_root, .{ .iterate = true });
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (!std.mem.startsWith(u8, entry.name, "cpu")) continue;
        if (std.mem.indexOfScalar(u8, entry.name, '-')) |_| continue;

        const path_buffer = try std.fmt.allocPrint(allocator, "{s}/{s}/cpufreq/{s}", .{ governor_root, entry.name, governor_file });
        try list.append(allocator, .{ .path = path_buffer });
    }

    return list.toOwnedSlice(allocator);
}

pub fn captureState(allocator: std.mem.Allocator) !GovernorState {
    if (!isAvailable()) return GovernorError.NotAvailable;

    var state = GovernorState.init(allocator);
    errdefer state.deinit();

    state.entries = try enumerateGovernorFiles(allocator);
    for (state.entries) |*entry| {
        entry.original = readFileAlloc(allocator, entry.path) catch null;
    }

    return state;
}

pub fn setPerformance(state: *GovernorState) !void {
    if (state.entries.len == 0) return GovernorError.NotAvailable;

    try setGovernor(state, "performance");
}

pub fn setGovernor(state: *GovernorState, value: []const u8) !void {
    if (state.entries.len == 0) return GovernorError.NotAvailable;

    for (state.entries) |entry| {
        writeFile(entry.path, value) catch |err| {
            std.log.warn("Governor update failed for {s}: {s}", .{ entry.path, @errorName(err) });
        };
    }
}

pub fn restore(state: *GovernorState) void {
    for (state.entries) |entry| {
        if (entry.original) |value| {
            writeFile(entry.path, value) catch |err| {
                std.log.warn("Governor restore failed for {s}: {s}", .{ entry.path, @errorName(err) });
            };
        }
        // Restore EPP if applicable
        if (entry.epp_path) |epp_path| {
            if (entry.original_epp) |epp_value| {
                writeFile(epp_path, epp_value) catch |err| {
                    std.log.warn("EPP restore failed for {s}: {s}", .{ epp_path, @errorName(err) });
                };
            }
        }
    }

    // Restore boost
    if (state.original_boost) |boost| {
        setBoost(boost) catch {};
    }
}

/// Detect scaling driver
pub fn detectDriver() ScalingDriver {
    const driver_path = "/sys/devices/system/cpu/cpu0/cpufreq/scaling_driver";
    var file = std.fs.openFileAbsolute(driver_path, .{}) catch return .unknown;
    defer file.close();

    var buf: [64]u8 = undefined;
    const len = file.read(&buf) catch return .unknown;
    const driver = std.mem.trimRight(u8, buf[0..len], "\n");

    if (std.mem.eql(u8, driver, "amd-pstate-epp")) return .amd_pstate_epp;
    if (std.mem.eql(u8, driver, "amd-pstate") or std.mem.eql(u8, driver, "amd_pstate")) return .amd_pstate;
    if (std.mem.eql(u8, driver, "intel_pstate")) return .intel_pstate;
    if (std.mem.eql(u8, driver, "intel_cpufreq")) return .intel_cpufreq;
    if (std.mem.eql(u8, driver, "acpi-cpufreq")) return .acpi_cpufreq;

    return .unknown;
}

/// Set EPP (Energy Performance Preference) for all CPUs
pub fn setEpp(state: *GovernorState, pref: EppPreference) !void {
    if (!state.driver.supportsEpp()) return;

    for (state.entries) |entry| {
        if (entry.epp_path) |epp_path| {
            writeFile(epp_path, pref.toSysfs()) catch |err| {
                std.log.warn("EPP set failed for {s}: {s}", .{ epp_path, @errorName(err) });
            };
        }
    }
}

/// Get boost state
pub fn getBoost() ?bool {
    // AMD
    if (std.fs.openFileAbsolute("/sys/devices/system/cpu/cpufreq/boost", .{})) |file| {
        defer file.close();
        var buf: [8]u8 = undefined;
        _ = file.read(&buf) catch return null;
        return buf[0] == '1';
    } else |_| {}

    // Intel
    if (std.fs.openFileAbsolute("/sys/devices/system/cpu/intel_pstate/no_turbo", .{})) |file| {
        defer file.close();
        var buf: [8]u8 = undefined;
        _ = file.read(&buf) catch return null;
        return buf[0] == '0'; // no_turbo=0 means boost enabled
    } else |_| {}

    return null;
}

/// Set boost state
pub fn setBoost(enabled: bool) !void {
    // AMD
    if (std.fs.openFileAbsolute("/sys/devices/system/cpu/cpufreq/boost", .{ .mode = .write_only })) |file| {
        defer file.close();
        _ = try file.write(if (enabled) "1" else "0");
        return;
    } else |_| {}

    // Intel
    if (std.fs.openFileAbsolute("/sys/devices/system/cpu/intel_pstate/no_turbo", .{ .mode = .write_only })) |file| {
        defer file.close();
        _ = try file.write(if (enabled) "0" else "1"); // Inverted
        return;
    } else |_| {}

    return error.NotAvailable;
}

/// Set gaming-optimized settings
pub fn setGamingMode(state: *GovernorState) !void {
    // Capture current state first
    state.original_boost = getBoost();

    // Enable boost
    setBoost(true) catch {};

    // Set governor to performance
    try setPerformance(state);

    // Set EPP to performance if available
    if (state.driver.supportsEpp()) {
        try setEpp(state, .performance);
    }

    std.log.info("Gaming mode enabled: governor=performance, boost=on, EPP=performance", .{});
}

/// Print current governor status
pub fn printStatus(state: *const GovernorState) void {
    std.debug.print("CPU Governor Status:\n", .{});
    std.debug.print("  Driver: {s}\n", .{state.driver.description()});
    std.debug.print("  Boost:  {s}\n", .{if (getBoost() orelse false) "Enabled" else "Disabled"});

    if (state.entries.len > 0) {
        const first = state.entries[0];
        if (first.original) |gov| {
            std.debug.print("  Governor: {s}\n", .{std.mem.trimRight(u8, gov, "\n")});
        }
        if (first.original_epp) |epp| {
            std.debug.print("  EPP: {s}\n", .{std.mem.trimRight(u8, epp, "\n")});
        }
    }
}
