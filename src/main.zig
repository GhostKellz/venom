//! VENOM CLI — Gaming Runtime Launcher
//!
//! Usage:
//!   venom run <game> [args...]  - Run game through VENOM
//!   venom info                   - Show system/GPU info
//!   venom version                - Show version

const std = @import("std");
const venom = @import("venom");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        printUsage();
        return;
    }

    const cmd = args[1];

    if (std.mem.eql(u8, cmd, "version") or std.mem.eql(u8, cmd, "--version") or std.mem.eql(u8, cmd, "-v")) {
        printVersion();
    } else if (std.mem.eql(u8, cmd, "help") or std.mem.eql(u8, cmd, "--help") or std.mem.eql(u8, cmd, "-h")) {
        printUsage();
    } else if (std.mem.eql(u8, cmd, "info")) {
        try printInfo();
    } else if (std.mem.eql(u8, cmd, "run")) {
        if (args.len < 3) {
            std.debug.print("Error: No game specified\n", .{});
            std.debug.print("Usage: venom run <game> [args...]\n", .{});
            return;
        }
        try runGame(allocator, args[2..]);
    } else {
        std.debug.print("Unknown command: {s}\n", .{cmd});
        printUsage();
    }
}

fn printVersion() void {
    std.debug.print(
        \\VENOM {s}
        \\NVIDIA-Native Gaming Runtime for Linux
        \\
        \\
    , .{venom.version});
}

fn printUsage() void {
    std.debug.print(
        \\VENOM — High-Performance Gaming Runtime
        \\
        \\Usage:
        \\  venom run <game> [args...]   Run game through VENOM runtime
        \\  venom info                   Show system information
        \\  venom version                Show version
        \\  venom help                   Show this help
        \\
        \\Options (for run):
        \\  --fps=<N>         Limit framerate to N FPS
        \\  --no-vrr          Disable VRR (G-Sync/FreeSync)
        \\  --no-hdr          Disable HDR passthrough
        \\  --low-latency     Enable low-latency mode (default)
        \\  --hud             Show performance overlay
        \\
        \\Examples:
        \\  venom run ./game
        \\  venom run steam steam://rungameid/1234
        \\  venom run --fps=144 ./game
        \\
        \\
    , .{});
}

fn printInfo() !void {
    std.debug.print(
        \\VENOM System Info
        \\=================
        \\Runtime Version: {s}
        \\
        \\Components:
        \\  Runtime:      Ready
        \\  Latency:      Ready
        \\  Compositor:   Stub (wlroots integration pending)
        \\  Vulkan Layer: Stub
        \\
        \\Features:
        \\  Low Latency:  Supported
        \\  VRR:          Supported (requires G-Sync/FreeSync display)
        \\  HDR:          Passthrough
        \\  Direct Scanout: Planned
        \\
        \\
    , .{venom.version});
}

fn runGame(allocator: std.mem.Allocator, game_args: []const []const u8) !void {
    std.debug.print("VENOM: Initializing runtime...\n", .{});

    const config = venom.Config{
        .low_latency = true,
        .vrr_enabled = true,
        .hdr_enabled = true,
    };

    const v = try venom.Venom.init(allocator, config);
    defer v.deinit();

    std.debug.print("VENOM: Starting runtime...\n", .{});
    try v.start();

    std.debug.print("VENOM: Launching game: {s}\n", .{game_args[0]});
    try v.runGame(game_args);

    std.debug.print("VENOM: Game launched. Monitoring...\n", .{});

    // In a real implementation, we'd wait for the game to exit
    // and provide real-time stats. For now, just print config.
    std.debug.print(
        \\
        \\Active Configuration:
        \\  Low Latency: {s}
        \\  VRR:         {s}
        \\  HDR:         {s}
        \\  Frame Limit: {d}
        \\
        \\
    , .{
        if (config.low_latency) "Enabled" else "Disabled",
        if (config.vrr_enabled) "Enabled" else "Disabled",
        if (config.hdr_enabled) "Enabled" else "Disabled",
        config.target_fps,
    });
}

test "main compiles" {
    // Basic compilation test
    _ = venom;
}
