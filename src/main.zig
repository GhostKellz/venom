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
const sessions = venom.sessions;
const governor = venom.governor;

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
    } else if (std.mem.eql(u8, cmd, "dlss")) {
        try printDlssInfo();
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
        \\  venom dlss                   Show DLSS 4.5 capabilities & presets
        \\  venom latency                Show latency presets
        \\  venom compositor             Show compositor capabilities
        \\  venom version                Show version
        \\  venom help                   Show this help
        \\
        \\Options (for run):
        \\  --fps=<N>                 Limit framerate to N FPS
        \\  --no-vrr                  Disable VRR (G-Sync/FreeSync)
        \\  --no-hdr                  Disable HDR passthrough
        \\  --low-latency             Prefer low-latency mode (default)
        \\  --no-low-latency          Disable Reflex optimizations
        \\  --hud                     Show performance overlay
        \\  --gamescope               Launch inside Gamescope session
        \\  --gamescope-size=<WxH>    Override Gamescope resolution
        \\  --gamescope-refresh=<Hz>  Set Gamescope refresh rate
        \\  --no-gamescope-vrr        Disable Gamescope adaptive sync
        \\  --gamescope-flag=<flag>   Pass extra flag to Gamescope (repeat)
        \\  --no-governor             Skip CPU governor override
        \\  --force-governor=<name>   Force specific governor value
        \\
        \\DLSS Options (RTX 20+):
        \\  --dlss=<preset>           DLSS preset (quality, balanced, performance,
        \\                            mfg_2x, mfg_3x, mfg_4x, dynamic, max_fps)
        \\  --dlss-quality=<mode>     Explicit quality (ultra_performance, performance,
        \\                            balanced, quality, ultra_quality, dlaa)
        \\  --frame-gen=<mode>        Frame generation (enabled, multi_2x, multi_3x,
        \\                            multi_4x, dynamic, dynamic_6x) [RTX 40/50]
        \\  --dlss-rr                 Enable DLSS Ray Reconstruction [RTX 40+]
        \\
        \\Auto-HDR Options (RTX 20+, requires Gamescope):
        \\  --auto-hdr                Enable Auto-HDR for SDR games
        \\  --auto-hdr=<preset>       Auto-HDR preset (standard, vivid, accurate, cinema)
        \\  --sdr-brightness=<nits>   SDR content brightness (default: 203 nits)
        \\  --hdr-peak=<nits>         Peak HDR brightness target (default: 1000 nits)
        \\
        \\Examples:
        \\  venom run ./game
        \\  venom run --dlss=quality --frame-gen=enabled ./game
        \\  venom run --dlss=dynamic --fps=165 ./game  # RTX 50 Dynamic MFG
        \\  venom run --gamescope --auto-hdr=vivid ./game  # Auto-HDR
        \\  venom run --gamescope --fps=144 steam steam://rungameid/1234
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

fn printDlssInfo() !void {
    const nvdlss = nvprime.nvdlss;

    std.debug.print("VENOM DLSS Info (via nvprime.nvdlss)\n", .{});
    std.debug.print("====================================\n\n", .{});

    // Detect GPU and DLSS version
    const gpu_gen = nvdlss.detectGpuGeneration();
    const caps = nvdlss.GpuCapabilities.fromGeneration(gpu_gen);

    std.debug.print("GPU Generation: {s}\n", .{gpu_gen.name()});
    std.debug.print("Model Type:     {s}\n", .{caps.model_type.description()});
    std.debug.print("\n", .{});

    // Version info
    if (nvdlss.getVersion()) |version| {
        std.debug.print("DLSS Version:   {d}.{d}.{d}\n", .{ version.major, version.minor, version.patch });
    }
    std.debug.print("\n", .{});

    // Feature support
    std.debug.print("Feature Support:\n", .{});
    std.debug.print("  DLSS Super Resolution: {s}\n", .{if (caps.supports_dlss_sr) "Yes" else "No"});
    std.debug.print("  DLSS Frame Gen:        {s}\n", .{if (caps.supports_dlss_fg) "Yes (RTX 40+)" else "No"});
    std.debug.print("  DLSS Ray Recon:        {s}\n", .{if (caps.supports_dlss_rr) "Yes (DLSS 3.5+)" else "No"});
    std.debug.print("  Multi Frame Gen:       {s}\n", .{if (caps.supports_dlss_mfg) "Yes (RTX 50)" else "No"});
    std.debug.print("  Dynamic MFG:           {s}\n", .{if (caps.supports_dynamic_mfg) "Yes (DLSS 4.5+)" else "No"});
    std.debug.print("  RTX Video SR:          {s}\n", .{if (caps.supports_video_sr) "Yes" else "No"});
    std.debug.print("  RTX HDR:               {s}\n", .{if (caps.supports_rtx_hdr) "Yes" else "No"});
    std.debug.print("\n", .{});

    // Quality modes
    std.debug.print("Quality Modes:\n", .{});
    inline for (std.meta.fields(nvdlss.QualityMode)) |field| {
        const mode: nvdlss.QualityMode = @enumFromInt(field.value);
        std.debug.print("  {s}: {s}\n", .{ field.name, mode.description() });
    }
    std.debug.print("\n", .{});

    // Frame gen modes
    std.debug.print("Frame Generation Modes:\n", .{});
    inline for (std.meta.fields(nvdlss.FrameGenMode)) |field| {
        const mode: nvdlss.FrameGenMode = @enumFromInt(field.value);
        const rtx50_note = if (mode.requiresRtx50()) " [RTX 50]" else "";
        std.debug.print("  {s}: {s}{s}\n", .{ field.name, mode.description(), rtx50_note });
    }
    std.debug.print("\n", .{});

    // Presets
    std.debug.print("Presets:\n", .{});
    const preset_names = [_][]const u8{
        "quality", "balanced", "performance", "ultra_performance",
        "mfg_2x", "mfg_3x", "mfg_4x", "dynamic", "max_fps",
    };
    for (preset_names) |name| {
        const cfg = nvdlss.DlssConfig.fromPreset(name);
        const fg_name = @tagName(cfg.frame_gen);
        std.debug.print("  {s}: quality={s}, frame_gen={s}\n", .{
            name,
            @tagName(cfg.quality),
            fg_name,
        });
    }
    std.debug.print("\n", .{});

    // Recommended for current GPU
    const recommended_fg = nvdlss.getRecommendedFrameGen(gpu_gen, 165);
    std.debug.print("Recommended (165Hz): {s}\n", .{recommended_fg.description()});

    std.debug.print("\nUsage: venom run --dlss=<preset> --frame-gen=<mode> <game>\n", .{});
}

const RunOptions = struct {
    fps: ?u32 = null,
    vrr: bool = true,
    hdr: bool = true,
    low_latency: bool = true,
    show_hud: bool = false,
    gamescope_enabled: bool = false,
    gamescope_size: ?struct { w: u32, h: u32 } = null,
    gamescope_refresh_hz: ?u32 = null,
    gamescope_vrr: bool = true,
    gamescope_extra_flags: []const []const u8 = &.{},
    force_governor: GovernorMode = .auto,
    // DLSS options
    dlss_preset: ?[]const u8 = null, // DLSS preset name (quality, performance, etc)
    dlss_quality: ?[]const u8 = null, // Explicit quality mode
    frame_gen: ?[]const u8 = null, // Frame gen mode (enabled, multi_2x, dynamic, etc)
    ray_reconstruction: bool = false, // Enable DLSS Ray Reconstruction
    // Auto-HDR options (RTX HDR for SDR games)
    auto_hdr: bool = false, // Enable Auto-HDR
    auto_hdr_preset: ?[]const u8 = null, // Auto-HDR preset (standard, vivid, accurate, cinema)
    sdr_brightness: ?u32 = null, // SDR content brightness in nits (default 203)
    hdr_peak_nits: ?u32 = null, // Peak brightness target in nits
};

const GovernorMode = union(enum) {
    auto,
    skip,
    force: []const u8,
};

fn parseRunOptions(allocator: std.mem.Allocator, args: []const []const u8) !struct {
    opts: RunOptions,
    game_start: []const []const u8,
} {
    var opts = RunOptions{};
    var idx: usize = 0;

    var extra_flags: std.ArrayListUnmanaged([]const u8) = .empty;
    defer extra_flags.deinit(allocator);

    while (idx < args.len) : (idx += 1) {
        const arg = args[idx];
        if (!std.mem.startsWith(u8, arg, "--")) break;

        if (std.mem.startsWith(u8, arg, "--fps=")) {
            const value = arg[6..];
            opts.fps = try std.fmt.parseInt(u32, value, 10);
            continue;
        }
        if (std.mem.eql(u8, arg, "--no-vrr")) {
            opts.vrr = false;
            continue;
        }
        if (std.mem.eql(u8, arg, "--no-hdr")) {
            opts.hdr = false;
            continue;
        }
        if (std.mem.eql(u8, arg, "--low-latency")) {
            opts.low_latency = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--no-low-latency")) {
            opts.low_latency = false;
            continue;
        }
        if (std.mem.eql(u8, arg, "--hud")) {
            opts.show_hud = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--gamescope")) {
            opts.gamescope_enabled = true;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--gamescope-size=")) {
            const value = arg[17..];
            if (std.mem.indexOfScalar(u8, value, 'x')) |split| {
                const width = try std.fmt.parseInt(u32, value[0..split], 10);
                const height = try std.fmt.parseInt(u32, value[split + 1 ..], 10);
                opts.gamescope_size = .{ .w = width, .h = height };
            }
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--gamescope-refresh=")) {
            const value = arg[20..];
            opts.gamescope_refresh_hz = try std.fmt.parseInt(u32, value, 10);
            continue;
        }
        if (std.mem.eql(u8, arg, "--no-gamescope-vrr")) {
            opts.gamescope_vrr = false;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--gamescope-flag=")) {
            const value = arg[17..];
            if (value.len > 0) {
                try extra_flags.append(allocator, value);
            }
            continue;
        }
        if (std.mem.eql(u8, arg, "--no-governor")) {
            opts.force_governor = .skip;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--force-governor=")) {
            opts.force_governor = .{ .force = arg[17..] };
            continue;
        }
        // DLSS options
        if (std.mem.startsWith(u8, arg, "--dlss=")) {
            opts.dlss_preset = arg[7..];
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--dlss-quality=")) {
            opts.dlss_quality = arg[15..];
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--frame-gen=")) {
            opts.frame_gen = arg[12..];
            continue;
        }
        if (std.mem.eql(u8, arg, "--ray-reconstruction") or std.mem.eql(u8, arg, "--dlss-rr")) {
            opts.ray_reconstruction = true;
            continue;
        }
        // Auto-HDR options
        if (std.mem.eql(u8, arg, "--auto-hdr")) {
            opts.auto_hdr = true;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--auto-hdr=")) {
            opts.auto_hdr = true;
            opts.auto_hdr_preset = arg[11..];
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--sdr-brightness=")) {
            opts.sdr_brightness = try std.fmt.parseInt(u32, arg[17..], 10);
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--hdr-peak=")) {
            opts.hdr_peak_nits = try std.fmt.parseInt(u32, arg[11..], 10);
            continue;
        }

        // Unknown option, stop parsing and treat as game command
        break;
    }

    if (idx >= args.len) return error.NoGameSpecified;

    opts.gamescope_extra_flags = try extra_flags.toOwnedSlice(allocator);

    return .{ .opts = opts, .game_start = args[idx..] };
}

fn runGame(allocator: std.mem.Allocator, run_args: []const []const u8) !void {
    const parsed = parseRunOptions(allocator, run_args) catch |err| {
        std.debug.print("VENOM: Failed to parse options: {s}\n", .{@errorName(err)});
        return err;
    };
    defer allocator.free(parsed.opts.gamescope_extra_flags);

    var governor_state = governor.GovernorState.init(allocator);
    defer governor_state.deinit();

    if (parsed.game_start.len == 0) {
        std.debug.print("VENOM: No game specified after options\n", .{});
        return error.NoGameSpecified;
    }

    const game_args = parsed.game_start;
    const user_opts = parsed.opts;

    std.debug.print("VENOM: Parsing runtime options...\n", .{});

    // Detect nested sessions early
    const nested_session = sessions.detectNestedSession();
    if (nested_session != .none) {
        std.debug.print("VENOM: Detected nested session: {s}\n", .{@tagName(nested_session)});
    }

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

    var runtime_config = venom.Config{
        .low_latency = user_opts.low_latency,
        .target_fps = user_opts.fps orelse 0,
        .vrr_enabled = user_opts.vrr,
        .hdr_enabled = user_opts.hdr,
        .show_hud = user_opts.show_hud,
        .latency_preset = if (user_opts.low_latency) .balanced else .default,
    };

    if (!supports_reflex and runtime_config.low_latency) {
        std.debug.print("VENOM: Disabling low-latency mode (Reflex unsupported)\n", .{});
        runtime_config.low_latency = false;
        runtime_config.latency_preset = .default;
    }

    if (user_opts.force_governor != .skip) {
        governor_state = governor.captureState(allocator) catch |err| blk: {
            if (err == error.NotAvailable) break :blk governor_state;
            std.debug.print("VENOM: Governor capture failed: {s}\n", .{@errorName(err)});
            break :blk governor_state;
        };
        switch (user_opts.force_governor) {
            .force => |value| {
                if (value.len > 0) {
                    governor.setGovernor(&governor_state, value) catch |err| {
                        std.debug.print("VENOM: Governor set failed: {s}\n", .{@errorName(err)});
                    };
                }
            },
            .auto => governor.setPerformance(&governor_state) catch |err| {
                std.debug.print("VENOM: Governor performance set failed: {s}\n", .{@errorName(err)});
            },
            else => {},
        }
    }

    const v = try venom.Venom.init(allocator, runtime_config);
    defer v.deinit();

    std.debug.print("VENOM: Starting runtime...\n", .{});
    try v.start();

    var gamescope_session = sessions.GamescopeSession.init(allocator);
    defer gamescope_session.deinit();
    var gamescope_cmd: sessions.GamescopeCommand = .{};
    defer gamescope_cmd.deinit(allocator);

    const launch_args = if (user_opts.gamescope_enabled) blk: {
        if (gamescope_session.isRunning()) {
            std.debug.print("VENOM: Gamescope already running, skipping nested launch\n", .{});
            break :blk game_args;
        }
        if (!sessions.isGamescopePresent()) {
            std.debug.print("VENOM: --gamescope requested but binary missing\n", .{});
            break :blk game_args;
        }

        const cmd = sessions.buildGamescopeCommand(allocator, .{
            .width = if (user_opts.gamescope_size) |sz| sz.w else null,
            .height = if (user_opts.gamescope_size) |sz| sz.h else null,
            .refresh_hz = user_opts.gamescope_refresh_hz,
            .hdr = runtime_config.hdr_enabled,
            .vrr = user_opts.gamescope_vrr,
            .extra_flags = user_opts.gamescope_extra_flags,
            // Auto-HDR options
            .auto_hdr = user_opts.auto_hdr,
            .sdr_content_nits = user_opts.sdr_brightness,
            .hdr_peak_nits = user_opts.hdr_peak_nits,
        }, game_args) catch |err| {
            std.debug.print("VENOM: Failed to build Gamescope command: {s}\n", .{@errorName(err)});
            break :blk game_args;
        };
        gamescope_cmd = cmd;

        std.debug.print("VENOM: Launching Gamescope wrapper\n", .{});
        gamescope_session.start(cmd.args) catch |err| {
            std.debug.print("VENOM: Gamescope startup failed: {s}\n", .{@errorName(err)});
            break :blk game_args;
        };
        break :blk cmd.args;
    } else game_args;

    const launch_target = launch_args[launch_args.len - game_args.len];
    std.debug.print("VENOM: Launching game: {s}\n", .{launch_target});
    v.runGame(launch_args) catch |err| {
        std.debug.print("VENOM: Game launch failed: {s}\n", .{@errorName(err)});
        if (gamescope_session.isRunning()) gamescope_session.stop();
        return err;
    };

    std.debug.print("VENOM: Game launched. Monitoring...\n", .{});

    if (user_opts.gamescope_enabled and gamescope_session.isRunning()) {
        std.debug.print("VENOM: Waiting for Gamescope session to exit\n", .{});
        gamescope_session.wait() catch |err| {
            std.debug.print("VENOM: Gamescope wait failed: {s}\n", .{@errorName(err)});
        };
    }

    // Build DLSS configuration string
    const nvdlss = nvprime.nvdlss;
    var dlss_config: ?nvdlss.DlssConfig = null;

    if (user_opts.dlss_preset) |preset| {
        dlss_config = nvdlss.DlssConfig.fromPreset(preset);
        std.debug.print("VENOM: DLSS preset '{s}' applied\n", .{preset});
    }

    // Parse frame-gen override if provided
    if (user_opts.frame_gen) |fg_str| {
        if (dlss_config == null) dlss_config = .{};
        if (std.mem.eql(u8, fg_str, "enabled")) {
            dlss_config.?.frame_gen = .enabled;
        } else if (std.mem.eql(u8, fg_str, "multi_2x")) {
            dlss_config.?.frame_gen = .multi_2x;
        } else if (std.mem.eql(u8, fg_str, "multi_3x")) {
            dlss_config.?.frame_gen = .multi_3x;
        } else if (std.mem.eql(u8, fg_str, "multi_4x")) {
            dlss_config.?.frame_gen = .multi_4x;
        } else if (std.mem.eql(u8, fg_str, "dynamic")) {
            dlss_config.?.frame_gen = .dynamic;
        } else if (std.mem.eql(u8, fg_str, "dynamic_6x")) {
            dlss_config.?.frame_gen = .dynamic_6x;
        }
        std.debug.print("VENOM: Frame Gen mode: {s}\n", .{@tagName(dlss_config.?.frame_gen)});
    }

    if (user_opts.ray_reconstruction) {
        if (dlss_config == null) dlss_config = .{};
        dlss_config.?.ray_reconstruction = true;
        std.debug.print("VENOM: DLSS Ray Reconstruction enabled\n", .{});
    }

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
    , .{
        if (runtime_config.low_latency) "Enabled" else "Disabled",
        @tagName(runtime_config.latency_preset),
        if (runtime_config.vrr_enabled) "Enabled" else "Disabled",
        if (runtime_config.hdr_enabled) "Enabled" else "Disabled",
        if (runtime_config.target_fps == 0) "Unlimited" else "Limited",
        if (gpu_detected) "Yes" else "No",
        if (supports_reflex) "Yes" else "No",
        if (supports_dlss) "Yes" else "No",
    });

    // Print DLSS configuration if set
    if (dlss_config) |cfg| {
        std.debug.print(
            \\DLSS Configuration:
            \\  Quality Mode:   {s}
            \\  Frame Gen:      {s}
            \\  Ray Recon:      {s}
            \\
            \\
        , .{
            @tagName(cfg.quality),
            cfg.frame_gen.description(),
            if (cfg.ray_reconstruction) "Enabled" else "Disabled",
        });
    } else {
        std.debug.print("\n", .{});
    }
}

test "main compiles" {
    // Basic compilation test
    _ = venom;
}
