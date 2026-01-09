//! NUMA and CCX awareness for AMD Zen CPUs
//!
//! Provides topology detection and CPU affinity optimization for:
//! - AMD Zen 5 (Ryzen 9000 series, EPYC 9005 series)
//! - AMD Zen 4 (Ryzen 7000 series)
//! - AMD Zen 3 (Ryzen 5000 series)
//! - Intel Alder Lake+ (P-core/E-core detection)
//!
//! Key optimizations:
//! - Prefer single CCX for cache locality (Zen 3D V-Cache)
//! - Avoid cross-CCD communication latency
//! - Pin game threads to performance cores (Intel hybrid)

const std = @import("std");

/// CPU architecture type
pub const CpuArchitecture = enum {
    unknown,
    amd_zen3,
    amd_zen4,
    amd_zen5,
    intel_alderlake,
    intel_raptorlake,
    intel_arrowlake,
    other,

    pub fn description(self: CpuArchitecture) []const u8 {
        return switch (self) {
            .unknown => "Unknown",
            .amd_zen3 => "AMD Zen 3 (Ryzen 5000/EPYC 7003)",
            .amd_zen4 => "AMD Zen 4 (Ryzen 7000/EPYC 9004)",
            .amd_zen5 => "AMD Zen 5 (Ryzen 9000/EPYC 9005)",
            .intel_alderlake => "Intel Alder Lake (12th Gen)",
            .intel_raptorlake => "Intel Raptor Lake (13th/14th Gen)",
            .intel_arrowlake => "Intel Arrow Lake (Core Ultra 200)",
            .other => "Other",
        };
    }

    pub fn hasHybridCores(self: CpuArchitecture) bool {
        return switch (self) {
            .intel_alderlake, .intel_raptorlake, .intel_arrowlake => true,
            else => false,
        };
    }

    pub fn hasCcx(self: CpuArchitecture) bool {
        return switch (self) {
            .amd_zen3, .amd_zen4, .amd_zen5 => true,
            else => false,
        };
    }

    pub fn hasVcache(self: CpuArchitecture) bool {
        return switch (self) {
            .amd_zen3, .amd_zen4, .amd_zen5 => true, // 3D V-Cache variants
            else => false,
        };
    }
};

/// CCX (Core Complex) information
pub const CcxInfo = struct {
    id: u32,
    core_count: u32,
    first_core: u32,
    last_core: u32,
    l3_cache_mb: u32,
    is_vcache: bool,
};

/// NUMA node information
pub const NumaNode = struct {
    id: u32,
    cpu_count: u32,
    cpus: []u32,
    memory_mb: u64,
    ccxs: []CcxInfo,
};

/// CPU topology information
pub const CpuTopology = struct {
    allocator: std.mem.Allocator,
    architecture: CpuArchitecture,
    total_cores: u32,
    physical_cores: u32,
    threads_per_core: u32,
    numa_nodes: []NumaNode,
    ccx_count: u32,
    ccd_count: u32,
    has_vcache: bool,
    vcache_ccx: ?u32,
    performance_cores: []u32,
    efficiency_cores: []u32,

    pub fn deinit(self: *CpuTopology) void {
        for (self.numa_nodes) |node| {
            self.allocator.free(node.cpus);
            self.allocator.free(node.ccxs);
        }
        if (self.numa_nodes.len > 0) self.allocator.free(self.numa_nodes);
        if (self.performance_cores.len > 0) self.allocator.free(self.performance_cores);
        if (self.efficiency_cores.len > 0) self.allocator.free(self.efficiency_cores);
    }
};

/// Detect CPU architecture from /proc/cpuinfo
pub fn detectArchitecture() CpuArchitecture {
    var file = std.fs.openFileAbsolute("/proc/cpuinfo", .{}) catch return .unknown;
    defer file.close();

    var buf: [4096]u8 = undefined;
    const len = file.read(&buf) catch return .unknown;
    const content = buf[0..len];

    // Check for AMD
    if (std.mem.indexOf(u8, content, "AuthenticAMD") != null or
        std.mem.indexOf(u8, content, "AMD") != null)
    {
        // Detect Zen generation from family/model
        if (std.mem.indexOf(u8, content, "Zen 5") != null or
            std.mem.indexOf(u8, content, "Ryzen 9 9") != null or
            std.mem.indexOf(u8, content, "9950X") != null or
            std.mem.indexOf(u8, content, "9900X") != null)
        {
            return .amd_zen5;
        }
        if (std.mem.indexOf(u8, content, "Zen 4") != null or
            std.mem.indexOf(u8, content, "Ryzen 9 7") != null or
            std.mem.indexOf(u8, content, "7950X") != null or
            std.mem.indexOf(u8, content, "7900X") != null)
        {
            return .amd_zen4;
        }
        if (std.mem.indexOf(u8, content, "Zen 3") != null or
            std.mem.indexOf(u8, content, "Ryzen 9 5") != null or
            std.mem.indexOf(u8, content, "5950X") != null or
            std.mem.indexOf(u8, content, "5900X") != null)
        {
            return .amd_zen3;
        }
    }

    // Check for Intel
    if (std.mem.indexOf(u8, content, "GenuineIntel") != null) {
        if (std.mem.indexOf(u8, content, "Core Ultra") != null or
            std.mem.indexOf(u8, content, "Arrow Lake") != null)
        {
            return .intel_arrowlake;
        }
        if (std.mem.indexOf(u8, content, "13th Gen") != null or
            std.mem.indexOf(u8, content, "14th Gen") != null or
            std.mem.indexOf(u8, content, "Raptor Lake") != null)
        {
            return .intel_raptorlake;
        }
        if (std.mem.indexOf(u8, content, "12th Gen") != null or
            std.mem.indexOf(u8, content, "Alder Lake") != null)
        {
            return .intel_alderlake;
        }
    }

    return .other;
}

/// Get total CPU count from sysfs
pub fn getCpuCount() u32 {
    var dir = std.fs.openDirAbsolute("/sys/devices/system/cpu", .{ .iterate = true }) catch return 1;
    defer dir.close();

    var count: u32 = 0;
    var iter = dir.iterate();
    while (iter.next() catch null) |entry| {
        if (std.mem.startsWith(u8, entry.name, "cpu") and
            entry.name.len > 3 and
            std.ascii.isDigit(entry.name[3]))
        {
            count += 1;
        }
    }

    return if (count > 0) count else 1;
}

/// Read NUMA node information
fn readNumaNodes(allocator: std.mem.Allocator) ![]NumaNode {
    var nodes = std.ArrayList(NumaNode).init(allocator);
    errdefer nodes.deinit();

    var dir = std.fs.openDirAbsolute("/sys/devices/system/node", .{ .iterate = true }) catch {
        // No NUMA, create single fake node
        var cpus = std.ArrayList(u32).init(allocator);
        const cpu_count = getCpuCount();
        for (0..cpu_count) |i| {
            try cpus.append(@intCast(i));
        }

        try nodes.append(.{
            .id = 0,
            .cpu_count = cpu_count,
            .cpus = try cpus.toOwnedSlice(),
            .memory_mb = 0,
            .ccxs = &.{},
        });
        return nodes.toOwnedSlice();
    };
    defer dir.close();

    var iter = dir.iterate();
    while (iter.next() catch null) |entry| {
        if (!std.mem.startsWith(u8, entry.name, "node")) continue;

        const node_id = std.fmt.parseInt(u32, entry.name[4..], 10) catch continue;

        // Read CPUs in this node
        var cpus = std.ArrayList(u32).init(allocator);
        errdefer cpus.deinit();

        const cpulist_path = try std.fmt.allocPrint(allocator, "/sys/devices/system/node/{s}/cpulist", .{entry.name});
        defer allocator.free(cpulist_path);

        if (std.fs.openFileAbsolute(cpulist_path, .{})) |file| {
            defer file.close();
            var buf: [256]u8 = undefined;
            const len = file.read(&buf) catch 0;
            if (len > 0) {
                // Parse CPU list (e.g., "0-7,16-23")
                const list = std.mem.trimRight(u8, buf[0..len], "\n");
                var ranges = std.mem.splitScalar(u8, list, ',');
                while (ranges.next()) |range| {
                    if (std.mem.indexOf(u8, range, "-")) |dash| {
                        const start = std.fmt.parseInt(u32, range[0..dash], 10) catch continue;
                        const end = std.fmt.parseInt(u32, range[dash + 1 ..], 10) catch continue;
                        for (start..end + 1) |cpu| {
                            try cpus.append(@intCast(cpu));
                        }
                    } else {
                        const cpu = std.fmt.parseInt(u32, range, 10) catch continue;
                        try cpus.append(cpu);
                    }
                }
            }
        } else |_| {}

        try nodes.append(.{
            .id = node_id,
            .cpu_count = @intCast(cpus.items.len),
            .cpus = try cpus.toOwnedSlice(),
            .memory_mb = 0,
            .ccxs = &.{},
        });
    }

    return nodes.toOwnedSlice();
}

/// Detect 3D V-Cache CCX
fn detectVcacheCcx() ?u32 {
    // V-Cache is typically on CCX 0 (first CCD)
    // Detection via L3 cache size comparison
    const l3_path = "/sys/devices/system/cpu/cpu0/cache/index3/size";
    var file = std.fs.openFileAbsolute(l3_path, .{}) catch return null;
    defer file.close();

    var buf: [32]u8 = undefined;
    const len = file.read(&buf) catch return null;
    const size_str = std.mem.trimRight(u8, buf[0..len], "K\n");
    const size_kb = std.fmt.parseInt(u32, size_str, 10) catch return null;

    // V-Cache chips have 96MB L3 per CCX (vs 32MB standard)
    if (size_kb >= 90000) { // 90MB+
        return 0; // V-Cache CCX
    }

    return null;
}

/// Detect full CPU topology
pub fn detectTopology(allocator: std.mem.Allocator) !CpuTopology {
    const arch = detectArchitecture();
    const total_cores = getCpuCount();
    const numa_nodes = try readNumaNodes(allocator);
    const vcache_ccx = detectVcacheCcx();

    // Calculate CCX/CCD count (AMD Zen)
    var ccx_count: u32 = 1;
    var ccd_count: u32 = 1;

    if (arch.hasCcx()) {
        // Zen 5: 8 cores per CCX, 2 CCX per CCD
        // Zen 4: 8 cores per CCX, 2 CCX per CCD
        // Zen 3: 8 cores per CCX, 2 CCX per CCD
        const cores_per_ccx: u32 = 8;
        ccx_count = (total_cores / 2 + cores_per_ccx - 1) / cores_per_ccx;
        ccd_count = (ccx_count + 1) / 2;
    }

    // Detect hybrid cores (Intel)
    var p_cores = std.ArrayList(u32).init(allocator);
    var e_cores = std.ArrayList(u32).init(allocator);

    if (arch.hasHybridCores()) {
        // Read core types from sysfs
        for (0..total_cores) |cpu| {
            const type_path = try std.fmt.allocPrint(allocator, "/sys/devices/system/cpu/cpu{d}/topology/core_type", .{cpu});
            defer allocator.free(type_path);

            if (std.fs.openFileAbsolute(type_path, .{})) |file| {
                defer file.close();
                var buf: [32]u8 = undefined;
                const len = file.read(&buf) catch continue;
                const core_type = std.mem.trimRight(u8, buf[0..len], "\n");

                if (std.mem.eql(u8, core_type, "performance") or std.mem.eql(u8, core_type, "0")) {
                    try p_cores.append(@intCast(cpu));
                } else {
                    try e_cores.append(@intCast(cpu));
                }
            } else |_| {
                // Default to P-core if unknown
                try p_cores.append(@intCast(cpu));
            }
        }
    }

    return CpuTopology{
        .allocator = allocator,
        .architecture = arch,
        .total_cores = total_cores,
        .physical_cores = total_cores / 2, // Assume SMT
        .threads_per_core = 2,
        .numa_nodes = numa_nodes,
        .ccx_count = ccx_count,
        .ccd_count = ccd_count,
        .has_vcache = vcache_ccx != null,
        .vcache_ccx = vcache_ccx,
        .performance_cores = try p_cores.toOwnedSlice(),
        .efficiency_cores = try e_cores.toOwnedSlice(),
    };
}

/// CPU affinity mask
pub const AffinityMask = struct {
    cpus: []u32,

    pub fn toLinuxMask(self: AffinityMask) u64 {
        var mask: u64 = 0;
        for (self.cpus) |cpu| {
            if (cpu < 64) {
                mask |= (@as(u64, 1) << @intCast(cpu));
            }
        }
        return mask;
    }
};

/// Get optimal affinity for gaming
pub fn getGamingAffinity(topology: *const CpuTopology, allocator: std.mem.Allocator) !AffinityMask {
    var cpus = std.ArrayList(u32).init(allocator);
    errdefer cpus.deinit();

    // Strategy varies by architecture
    switch (topology.architecture) {
        .amd_zen3, .amd_zen4, .amd_zen5 => {
            // Prefer V-Cache CCX if available, otherwise first CCX
            const target_ccx: u32 = topology.vcache_ccx orelse 0;
            const cores_per_ccx: u32 = 8;
            const start_core = target_ccx * cores_per_ccx;
            const end_core = @min(start_core + cores_per_ccx, topology.total_cores);

            // Add both threads of each core in CCX
            for (start_core..end_core) |core| {
                try cpus.append(@intCast(core));
                // SMT thread is usually core + physical_cores
                if (core + topology.physical_cores < topology.total_cores) {
                    try cpus.append(@intCast(core + topology.physical_cores));
                }
            }
        },
        .intel_alderlake, .intel_raptorlake, .intel_arrowlake => {
            // Use P-cores only for gaming
            for (topology.performance_cores) |cpu| {
                try cpus.append(cpu);
            }
        },
        else => {
            // Use all cores
            for (0..topology.total_cores) |cpu| {
                try cpus.append(@intCast(cpu));
            }
        },
    }

    return AffinityMask{
        .cpus = try cpus.toOwnedSlice(),
    };
}

/// Set CPU affinity for a process
pub fn setProcessAffinity(pid: std.posix.pid_t, mask: AffinityMask) !void {
    const linux_mask = mask.toLinuxMask();

    // Use sched_setaffinity syscall
    const result = std.os.linux.syscall3(
        .sched_setaffinity,
        @intCast(pid),
        @sizeOf(u64),
        @intFromPtr(&linux_mask),
    );

    if (result != 0) {
        return error.SetAffinityFailed;
    }
}

/// Print topology information
pub fn printTopology(topology: *const CpuTopology) void {
    std.debug.print("CPU Topology:\n", .{});
    std.debug.print("  Architecture: {s}\n", .{topology.architecture.description()});
    std.debug.print("  Total Cores:  {d}\n", .{topology.total_cores});
    std.debug.print("  Physical:     {d}\n", .{topology.physical_cores});
    std.debug.print("  SMT:          {d} threads/core\n", .{topology.threads_per_core});
    std.debug.print("  NUMA Nodes:   {d}\n", .{topology.numa_nodes.len});

    if (topology.architecture.hasCcx()) {
        std.debug.print("  CCX Count:    {d}\n", .{topology.ccx_count});
        std.debug.print("  CCD Count:    {d}\n", .{topology.ccd_count});
        if (topology.has_vcache) {
            std.debug.print("  V-Cache:      Yes (CCX {d})\n", .{topology.vcache_ccx.?});
        }
    }

    if (topology.architecture.hasHybridCores()) {
        std.debug.print("  P-Cores:      {d}\n", .{topology.performance_cores.len});
        std.debug.print("  E-Cores:      {d}\n", .{topology.efficiency_cores.len});
    }

    std.debug.print("\n", .{});
}

test "architecture detection" {
    const arch = detectArchitecture();
    std.debug.print("Detected: {s}\n", .{arch.description()});
}

test "cpu count" {
    const count = getCpuCount();
    std.debug.print("CPUs: {d}\n", .{count});
    try std.testing.expect(count > 0);
}
