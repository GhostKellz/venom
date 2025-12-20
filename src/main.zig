//! VENOM CLI — Gaming Runtime Launcher
//!
//! Usage:
//!   venom run <game> [args...]  - Run game through VENOM
//!   venom info                   - Show system/GPU info
//!   venom gpu                    - Show GPU details via nvprime
//!   venom version                - Show version

const std = @import("std");
const venom = @import("venom");
const nvprime = @import("nvprime");

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
        try printInfo(allocator);
    } else if (std.mem.eql(u8, cmd, "gpu")) {
        try printGpuInfo(allocator);
    } else if (std.mem.eql(u8, cmd, "latency")) {
        printLatencyInfo();
    } else if (std.mem.eql(u8, cmd, "compositor")) {
        try printCompositorInfo(allocator);
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
        \\  venom gpu                    Show GPU details (via nvprime)
        \\  venom latency                Show latency presets
        \\  venom compositor             Show compositor capabilities
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

fn printInfo(allocator: std.mem.Allocator) !void {
    std.debug.print(
        \\VENOM System Info
        \\=================
        \\Runtime Version: {s}
        \\NVPrime Version: {s}
        \\
        \\Components:
        \\  Runtime:      Ready
        \\  Latency:      Ready (nvlatency integrated)
        \\  Compositor:   Stub (wlroots integration pending)
        \\  Vulkan Layer: Stub (nvvk integrated)
        \\
        \\Features:
        \\  Low Latency:  Supported (NVIDIA Reflex via nvlatency)
        \\  VRR:          Supported (G-Sync/FreeSync via nvsync)
        \\  HDR:          Passthrough
        \\  Direct Scanout: Planned
        \\
        \\
    , .{ venom.version, nvprime.version.string });

    // Try to detect GPU
    std.debug.print("GPU Detection:\n", .{});
    nvprime.nvml.init() catch |err| {
        std.debug.print("  NVML: Not available ({s})\n", .{@errorName(err)});
        return;
    };
    defer nvprime.nvml.shutdown();

    // detectGpus caches internally, nvcaps.deinit() frees the cache
    const gpus = nvprime.nvcaps.detectGpus(allocator) catch |err| {
        std.debug.print("  GPU detection failed: {s}\n", .{@errorName(err)});
        return;
    };
    defer nvprime.nvcaps.deinit();

    for (gpus) |gpu| {
        std.debug.print("  GPU {d}: {s}\n", .{ gpu.index, std.mem.sliceTo(&gpu.name, 0) });
        std.debug.print("    Architecture: {s}\n", .{@tagName(gpu.architecture)});
        std.debug.print("    VRAM: {d} MB\n", .{gpu.vram_total_mb});
        std.debug.print("    Reflex: {s}, DLSS: {s}, RTX: {s}\n", .{
            if (gpu.supports_reflex) "Yes" else "No",
            if (gpu.supports_dlss) "Yes" else "No",
            if (gpu.supports_rtx) "Yes" else "No",
        });
    }
    std.debug.print("\n", .{});
}

fn printGpuInfo(allocator: std.mem.Allocator) !void {
    std.debug.print("VENOM GPU Info (via nvprime)\n", .{});
    std.debug.print("============================\n\n", .{});

    nvprime.nvml.init() catch |err| {
        std.debug.print("Error: NVML not available ({s})\n", .{@errorName(err)});
        std.debug.print("Make sure NVIDIA driver is installed.\n", .{});
        return;
    };
    defer nvprime.nvml.shutdown();

    // detectGpus caches internally, nvcaps.deinit() frees the cache
    const gpus = nvprime.nvcaps.detectGpus(allocator) catch |err| {
        std.debug.print("Error: GPU detection failed ({s})\n", .{@errorName(err)});
        return;
    };
    defer nvprime.nvcaps.deinit();

    if (gpus.len == 0) {
        std.debug.print("No NVIDIA GPUs detected.\n", .{});
        return;
    }

    const summary = nvprime.nvcaps.getSystemSummary(gpus);
    std.debug.print("System Summary:\n", .{});
    std.debug.print("  GPU Count:    {d}\n", .{summary.gpu_count});
    std.debug.print("  Total VRAM:   {d} MB\n", .{summary.total_vram_mb});
    std.debug.print("  Architecture: {s}\n", .{@tagName(summary.best_architecture)});
    std.debug.print("  All RTX:      {s}\n", .{if (summary.all_support_rtx) "Yes" else "No"});
    std.debug.print("  All DLSS:     {s}\n", .{if (summary.all_support_dlss) "Yes" else "No"});
    std.debug.print("\n", .{});

    for (gpus) |gpu| {
        // Print GPU details
        std.debug.print("GPU {d}: {s}\n", .{ gpu.index, std.mem.sliceTo(&gpu.name, 0) });
        std.debug.print("  Architecture: {s}\n", .{@tagName(gpu.architecture)});
        std.debug.print("  VRAM: {d} MB / {d} MB\n", .{ gpu.vram_used_mb, gpu.vram_total_mb });
        std.debug.print("  Features: RTX={} DLSS={} DLSS3={} Reflex={}\n", .{
            gpu.supports_rtx,
            gpu.supports_dlss,
            gpu.supports_dlss3,
            gpu.supports_reflex,
        });
        std.debug.print("  State: {d}C, {d:.1}W, GPU {d}MHz\n", .{
            gpu.temperature_c,
            gpu.power_draw_w,
            gpu.gpu_clock_mhz,
        });
        std.debug.print("\n", .{});

        // Show recommended profile
        const profile = nvprime.nvcaps.getRecommendedProfile(gpu);
        std.debug.print("  Recommended Profile: {s}\n", .{@tagName(profile)});
        std.debug.print("    {s}\n\n", .{profile.description()});
    }
}

fn printCompositorInfo(allocator: std.mem.Allocator) !void {
    const compositor = venom.compositor;

    std.debug.print("VENOM Compositor Info\n", .{});
    std.debug.print("=====================\n\n", .{});

    std.debug.print("Compositor Version: {s}\n", .{compositor.version});
    std.debug.print("Wayland Session:    {s}\n", .{if (compositor.isWaylandSession()) "Yes" else "No"});
    std.debug.print("wlroots Available:  {s}\n", .{if (compositor.isWlrootsAvailable()) "Yes (checking...)" else "No"});
    std.debug.print("\n", .{});

    // Try to initialize compositor context to test wlroots loading
    std.debug.print("Initializing compositor context...\n", .{});
    const ctx = compositor.Context.init(allocator, .{}) catch |err| {
        std.debug.print("  Error: {s}\n", .{@errorName(err)});
        std.debug.print("\nCompositor initialization failed.\n", .{});
        std.debug.print("This is expected if wlroots is not installed.\n", .{});
        return;
    };
    defer ctx.deinit();

    std.debug.print("  Context created: {s}\n", .{@tagName(ctx.state)});

    // Start compositor (mock mode)
    ctx.start() catch |err| {
        std.debug.print("  Start failed: {s}\n", .{@errorName(err)});
        return;
    };

    std.debug.print("  State: {s}\n", .{@tagName(ctx.state)});

    // Show outputs
    const outputs = ctx.getOutputs();
    if (outputs.len > 0) {
        std.debug.print("\nDetected Outputs:\n", .{});
        for (outputs, 0..) |output, i| {
            std.debug.print("  Output {d}: {s}\n", .{ i, output.getName() });
            std.debug.print("    Resolution: {d}x{d} @ {d}Hz\n", .{ output.width, output.height, output.refreshHz() });
            std.debug.print("    VRR: {s}, HDR: {s}, Tearing: {s}\n", .{
                if (output.vrr_capable) "Capable" else "No",
                if (output.hdr_capable) "Capable" else "No",
                if (output.tearing_capable) "Capable" else "No",
            });
            if (output.max_luminance_nits > 0) {
                std.debug.print("    Max Luminance: {d} nits\n", .{output.max_luminance_nits});
            }
        }
    }

    std.debug.print("\nModes:\n", .{});
    inline for (std.meta.fields(compositor.Mode)) |field| {
        const mode: compositor.Mode = @enumFromInt(field.value);
        std.debug.print("  {s}: {s}\n", .{ field.name, mode.description() });
    }

    std.debug.print("\nHDR States:\n", .{});
    inline for (std.meta.fields(compositor.HdrState)) |field| {
        const state: compositor.HdrState = @enumFromInt(field.value);
        std.debug.print("  {s}: {s}\n", .{ field.name, state.description() });
    }

    std.debug.print("\nTearing Modes:\n", .{});
    inline for (std.meta.fields(compositor.TearingMode)) |field| {
        const mode: compositor.TearingMode = @enumFromInt(field.value);
        std.debug.print("  {s}: {s}\n", .{ field.name, mode.description() });
    }

    std.debug.print("\nCompositor initialized successfully!\n", .{});
}

fn printLatencyInfo() void {
    std.debug.print("VENOM Latency Presets (via nvprime.nvlatency)\n", .{});
    std.debug.print("=============================================\n\n", .{});

    inline for (std.meta.fields(nvprime.nvruntime.nvlatency.LatencyPreset)) |field| {
        const preset: nvprime.nvruntime.nvlatency.LatencyPreset = @enumFromInt(field.value);
        std.debug.print("  {s}:\n", .{field.name});
        std.debug.print("    {s}\n", .{preset.description()});
        std.debug.print("    Reflex Mode: {s}\n\n", .{@tagName(preset.getReflexMode())});
    }

    std.debug.print("Usage: venom run --latency=<preset> <game>\n", .{});
}

fn runGame(allocator: std.mem.Allocator, game_args: []const []const u8) !void {
    std.debug.print("VENOM: Initializing runtime...\n", .{});

    // Initialize nvprime for GPU queries
    nvprime.nvml.init() catch |err| {
        std.debug.print("VENOM: Warning - NVML not available ({s}), running in degraded mode\n", .{@errorName(err)});
    };
    defer nvprime.nvml.shutdown();

    // Detect GPU and set optimal config
    var gpu_detected = false;
    var supports_reflex = true;
    var supports_dlss = false;

    // Note: detectGpus caches the result internally in nvcaps, so don't free here
    if (nvprime.nvcaps.detectGpus(allocator)) |gpus| {
        // gpus are cached by nvcaps.deinit() handles cleanup
        if (gpus.len > 0) {
            const gpu = gpus[0]; // Primary GPU
            gpu_detected = true;
            supports_reflex = gpu.supports_reflex;
            supports_dlss = gpu.supports_dlss;

            std.debug.print("VENOM: Detected {s} ({s})\n", .{
                std.mem.sliceTo(&gpu.name, 0),
                @tagName(gpu.architecture),
            });
            std.debug.print("VENOM: Reflex: {s}, DLSS: {s}, VRAM: {d}MB\n", .{
                if (supports_reflex) "Yes" else "No",
                if (supports_dlss) "Yes" else "No",
                gpu.vram_total_mb,
            });
        }
    } else |_| {}

    const config = venom.Config{
        .low_latency = supports_reflex,
        .vrr_enabled = true,
        .hdr_enabled = true,
        .latency_preset = if (supports_reflex) .balanced else .default,
    };

    const v = try venom.Venom.init(allocator, config);
    defer v.deinit();

    std.debug.print("VENOM: Starting runtime...\n", .{});
    try v.start();

    std.debug.print("VENOM: Launching game: {s}\n", .{game_args[0]});
    try v.runGame(game_args);

    std.debug.print("VENOM: Game launched. Monitoring...\n", .{});

    // Print active configuration
    std.debug.print(
        \\
        \\Active Configuration:
        \\  Low Latency:    {s}
        \\  Latency Preset: {s}
        \\  VRR:            {s}
        \\  HDR:            {s}
        \\  Frame Limit:    {s}
        \\
        \\NVPrime Integration:
        \\  GPU Detected:   {s}
        \\  Reflex Ready:   {s}
        \\  DLSS Ready:     {s}
        \\
        \\
    , .{
        if (config.low_latency) "Enabled (Reflex)" else "Disabled",
        @tagName(config.latency_preset),
        if (config.vrr_enabled) "Enabled" else "Disabled",
        if (config.hdr_enabled) "Enabled" else "Disabled",
        if (config.target_fps == 0) "Unlimited" else "Limited",
        if (gpu_detected) "Yes" else "No",
        if (supports_reflex) "Yes" else "No",
        if (supports_dlss) "Yes" else "No",
    });
}

test "main compiles" {
    // Basic compilation test
    _ = venom;
}
