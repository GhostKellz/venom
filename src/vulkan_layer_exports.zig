//! VENOM Vulkan Layer Exports
//!
//! This module exports C functions for the Vulkan implicit layer.
//! It intercepts Vulkan calls to track frame timing and inject latency optimizations.

const std = @import("std");
const nvprime = @import("nvprime");

// ============================================================================
// Vulkan Types
// ============================================================================

const VkResult = enum(i32) {
    success = 0,
    not_ready = 1,
    timeout = 2,
    event_set = 3,
    event_reset = 4,
    incomplete = 5,
    error_out_of_host_memory = -1,
    error_out_of_device_memory = -2,
    error_initialization_failed = -3,
    error_device_lost = -4,
    error_memory_map_failed = -5,
    error_layer_not_present = -6,
    error_extension_not_present = -7,
    _,
};

const VkInstance = ?*opaque {};
const VkDevice = ?*opaque {};
const VkQueue = ?*opaque {};
const VkSwapchainKHR = u64;
const VkPhysicalDevice = ?*opaque {};
const VkSurfaceKHR = u64;
const VkFence = u64;
const VkSemaphore = u64;
const VkAllocationCallbacks = opaque {};
const VkBool32 = u32;
const VkFormat = u32;
const VkColorSpaceKHR = u32;
const VkPresentModeKHR = enum(u32) {
    immediate = 0,
    mailbox = 1,
    fifo = 2,
    fifo_relaxed = 3,
    _,
};
const VkSharingMode = u32;
const VkImageUsageFlags = u32;
const VkSurfaceTransformFlagBitsKHR = u32;
const VkCompositeAlphaFlagBitsKHR = u32;
const VkExtent2D = extern struct {
    width: u32,
    height: u32,
};

const VkSwapchainCreateInfoKHR = extern struct {
    sType: u32 = 1000001000, // VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    surface: VkSurfaceKHR = 0,
    minImageCount: u32 = 0,
    imageFormat: VkFormat = 0,
    imageColorSpace: VkColorSpaceKHR = 0,
    imageExtent: VkExtent2D = .{ .width = 0, .height = 0 },
    imageArrayLayers: u32 = 0,
    imageUsage: VkImageUsageFlags = 0,
    imageSharingMode: VkSharingMode = 0,
    queueFamilyIndexCount: u32 = 0,
    pQueueFamilyIndices: ?[*]const u32 = null,
    preTransform: VkSurfaceTransformFlagBitsKHR = 0,
    compositeAlpha: VkCompositeAlphaFlagBitsKHR = 0,
    presentMode: VkPresentModeKHR = .fifo,
    clipped: VkBool32 = 0,
    oldSwapchain: VkSwapchainKHR = 0,
};

const VkPresentInfoKHR = extern struct {
    sType: u32 = 1000001001, // VK_STRUCTURE_TYPE_PRESENT_INFO_KHR
    pNext: ?*const anyopaque = null,
    waitSemaphoreCount: u32 = 0,
    pWaitSemaphores: ?[*]const VkSemaphore = null,
    swapchainCount: u32 = 0,
    pSwapchains: ?[*]const VkSwapchainKHR = null,
    pImageIndices: ?[*]const u32 = null,
    pResults: ?[*]VkResult = null,
};

// VK_NV_low_latency2 structures
const VK_STRUCTURE_TYPE_LATENCY_SLEEP_MODE_INFO_NV: u32 = 1000505000;
const VK_STRUCTURE_TYPE_LATENCY_SLEEP_INFO_NV: u32 = 1000505001;
const VK_STRUCTURE_TYPE_SET_LATENCY_MARKER_INFO_NV: u32 = 1000505002;
const VK_STRUCTURE_TYPE_GET_LATENCY_MARKER_INFO_NV: u32 = 1000505003;
const VK_STRUCTURE_TYPE_LATENCY_TIMINGS_FRAME_REPORT_NV: u32 = 1000505004;
const VK_STRUCTURE_TYPE_LATENCY_SUBMISSION_PRESENT_ID_NV: u32 = 1000505005;
const VK_STRUCTURE_TYPE_OUT_OF_BAND_QUEUE_TYPE_INFO_NV: u32 = 1000505006;
const VK_STRUCTURE_TYPE_SWAPCHAIN_LATENCY_CREATE_INFO_NV: u32 = 1000505007;
const VK_STRUCTURE_TYPE_LATENCY_SURFACE_CAPABILITIES_NV: u32 = 1000505008;

const VkLatencyMarkerNV = enum(u32) {
    simulation_start = 0,
    simulation_end = 1,
    rendersubmit_start = 2,
    rendersubmit_end = 3,
    present_start = 4,
    present_end = 5,
    input_sample = 6,
    trigger_flash = 7,
    out_of_band_rendersubmit_start = 8,
    out_of_band_rendersubmit_end = 9,
    out_of_band_present_start = 10,
    out_of_band_present_end = 11,
    _,
};

const VkOutOfBandQueueTypeNV = enum(u32) {
    render = 0,
    present = 1,
    _,
};

const VkLatencySleepModeInfoNV = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_LATENCY_SLEEP_MODE_INFO_NV,
    pNext: ?*const anyopaque = null,
    lowLatencyMode: VkBool32 = 0,
    lowLatencyBoost: VkBool32 = 0,
    minimumIntervalUs: u32 = 0,
};

const VkLatencySleepInfoNV = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_LATENCY_SLEEP_INFO_NV,
    pNext: ?*const anyopaque = null,
    signalSemaphore: VkSemaphore = 0,
    value: u64 = 0,
};

const VkSetLatencyMarkerInfoNV = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_SET_LATENCY_MARKER_INFO_NV,
    pNext: ?*const anyopaque = null,
    presentID: u64 = 0,
    marker: VkLatencyMarkerNV = .simulation_start,
};

const VkLatencyTimingsFrameReportNV = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_LATENCY_TIMINGS_FRAME_REPORT_NV,
    pNext: ?*anyopaque = null,
    presentID: u64 = 0,
    inputSampleTimeUs: u64 = 0,
    simStartTimeUs: u64 = 0,
    simEndTimeUs: u64 = 0,
    renderSubmitStartTimeUs: u64 = 0,
    renderSubmitEndTimeUs: u64 = 0,
    presentStartTimeUs: u64 = 0,
    presentEndTimeUs: u64 = 0,
    driverStartTimeUs: u64 = 0,
    driverEndTimeUs: u64 = 0,
    osRenderQueueStartTimeUs: u64 = 0,
    osRenderQueueEndTimeUs: u64 = 0,
    gpuRenderStartTimeUs: u64 = 0,
    gpuRenderEndTimeUs: u64 = 0,
};

const VkGetLatencyMarkerInfoNV = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_GET_LATENCY_MARKER_INFO_NV,
    pNext: ?*const anyopaque = null,
    timingCount: u32 = 0,
    pTimings: ?[*]VkLatencyTimingsFrameReportNV = null,
};

const VkOutOfBandQueueTypeInfoNV = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_OUT_OF_BAND_QUEUE_TYPE_INFO_NV,
    pNext: ?*const anyopaque = null,
    queueType: VkOutOfBandQueueTypeNV = .render,
};

const VkSwapchainLatencyCreateInfoNV = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_SWAPCHAIN_LATENCY_CREATE_INFO_NV,
    pNext: ?*const anyopaque = null,
    latencyModeEnable: VkBool32 = 0,
};

// VK_KHR_present_id / VK_KHR_present_wait
const VK_STRUCTURE_TYPE_PRESENT_ID_KHR: u32 = 1000294000;
const VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PRESENT_ID_FEATURES_KHR: u32 = 1000294001;
const VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PRESENT_WAIT_FEATURES_KHR: u32 = 1000295000;

const VkPresentIdKHR = extern struct {
    sType: u32 = VK_STRUCTURE_TYPE_PRESENT_ID_KHR,
    pNext: ?*const anyopaque = null,
    swapchainCount: u32 = 0,
    pPresentIds: ?[*]const u64 = null,
};

const VkInstanceCreateInfo = extern struct {
    sType: u32 = 1, // VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    pApplicationInfo: ?*const anyopaque = null,
    enabledLayerCount: u32 = 0,
    ppEnabledLayerNames: ?[*]const [*:0]const u8 = null,
    enabledExtensionCount: u32 = 0,
    ppEnabledExtensionNames: ?[*]const [*:0]const u8 = null,
};

const VkDeviceCreateInfo = extern struct {
    sType: u32 = 3, // VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
    queueCreateInfoCount: u32 = 0,
    pQueueCreateInfos: ?*const anyopaque = null,
    enabledLayerCount: u32 = 0,
    ppEnabledLayerNames: ?[*]const [*:0]const u8 = null,
    enabledExtensionCount: u32 = 0,
    ppEnabledExtensionNames: ?[*]const [*:0]const u8 = null,
    pEnabledFeatures: ?*const anyopaque = null,
};

// Function pointer types
const PFN_vkVoidFunction = ?*const fn () callconv(.c) void;

// VK_NV_low_latency2 function pointers
const PFN_vkSetLatencySleepModeNV = *const fn (VkDevice, VkSwapchainKHR, *const VkLatencySleepModeInfoNV) callconv(.c) VkResult;
const PFN_vkLatencySleepNV = *const fn (VkDevice, VkSwapchainKHR, *const VkLatencySleepInfoNV) callconv(.c) VkResult;
const PFN_vkSetLatencyMarkerNV = *const fn (VkDevice, VkSwapchainKHR, *const VkSetLatencyMarkerInfoNV) callconv(.c) void;
const PFN_vkGetLatencyTimingsNV = *const fn (VkDevice, VkSwapchainKHR, *VkGetLatencyMarkerInfoNV) callconv(.c) void;
const PFN_vkQueueNotifyOutOfBandNV = *const fn (VkQueue, *const VkOutOfBandQueueTypeInfoNV) callconv(.c) void;

// VK_KHR_present_wait function pointer
const PFN_vkWaitForPresentKHR = *const fn (VkDevice, VkSwapchainKHR, u64, u64) callconv(.c) VkResult;
const PFN_vkGetInstanceProcAddr = *const fn (VkInstance, [*:0]const u8) callconv(.c) PFN_vkVoidFunction;
const PFN_vkGetDeviceProcAddr = *const fn (VkDevice, [*:0]const u8) callconv(.c) PFN_vkVoidFunction;
const PFN_vkCreateInstance = *const fn (*const VkInstanceCreateInfo, ?*const VkAllocationCallbacks, *VkInstance) callconv(.c) VkResult;
const PFN_vkDestroyInstance = *const fn (VkInstance, ?*const VkAllocationCallbacks) callconv(.c) void;
const PFN_vkCreateDevice = *const fn (VkPhysicalDevice, *const VkDeviceCreateInfo, ?*const VkAllocationCallbacks, *VkDevice) callconv(.c) VkResult;
const PFN_vkDestroyDevice = *const fn (VkDevice, ?*const VkAllocationCallbacks) callconv(.c) void;
const PFN_vkCreateSwapchainKHR = *const fn (VkDevice, *const VkSwapchainCreateInfoKHR, ?*const VkAllocationCallbacks, *VkSwapchainKHR) callconv(.c) VkResult;
const PFN_vkDestroySwapchainKHR = *const fn (VkDevice, VkSwapchainKHR, ?*const VkAllocationCallbacks) callconv(.c) void;
const PFN_vkQueuePresentKHR = *const fn (VkQueue, *const VkPresentInfoKHR) callconv(.c) VkResult;

// Layer chain link
const VkLayerInstanceLink = extern struct {
    pNext: ?*VkLayerInstanceLink,
    pfnNextGetInstanceProcAddr: PFN_vkGetInstanceProcAddr,
    pfnNextGetPhysicalDeviceProcAddr: PFN_vkGetInstanceProcAddr,
};

const VkLayerDeviceLink = extern struct {
    pNext: ?*VkLayerDeviceLink,
    pfnNextGetInstanceProcAddr: PFN_vkGetInstanceProcAddr,
    pfnNextGetDeviceProcAddr: PFN_vkGetDeviceProcAddr,
};

const VkLayerInstanceCreateInfo = extern struct {
    sType: u32,
    pNext: ?*const anyopaque,
    function: u32,
    u: extern union {
        pLayerInfo: *VkLayerInstanceLink,
    },
};

const VkLayerDeviceCreateInfo = extern struct {
    sType: u32,
    pNext: ?*const anyopaque,
    function: u32,
    u: extern union {
        pLayerInfo: *VkLayerDeviceLink,
    },
};

const VK_STRUCTURE_TYPE_LOADER_INSTANCE_CREATE_INFO: u32 = 47;
const VK_STRUCTURE_TYPE_LOADER_DEVICE_CREATE_INFO: u32 = 48;
const VK_LAYER_LINK_INFO: u32 = 0;

// ============================================================================
// Layer State
// ============================================================================

const InstanceData = struct {
    instance: VkInstance,
    next_gipa: PFN_vkGetInstanceProcAddr,
    next_destroy_instance: ?PFN_vkDestroyInstance = null,
};

const DeviceData = struct {
    device: VkDevice,
    instance: VkInstance,
    next_gdpa: PFN_vkGetDeviceProcAddr,
    next_destroy_device: ?PFN_vkDestroyDevice = null,
    next_create_swapchain: ?PFN_vkCreateSwapchainKHR = null,
    next_destroy_swapchain: ?PFN_vkDestroySwapchainKHR = null,
    next_queue_present: ?PFN_vkQueuePresentKHR = null,
    // VK_NV_low_latency2 functions
    next_set_latency_sleep_mode: ?PFN_vkSetLatencySleepModeNV = null,
    next_latency_sleep: ?PFN_vkLatencySleepNV = null,
    next_set_latency_marker: ?PFN_vkSetLatencyMarkerNV = null,
    next_get_latency_timings: ?PFN_vkGetLatencyTimingsNV = null,
    next_queue_notify_oob: ?PFN_vkQueueNotifyOutOfBandNV = null,
    // VK_KHR_present_wait
    next_wait_for_present: ?PFN_vkWaitForPresentKHR = null,
    // Extension availability
    has_low_latency2: bool = false,
    has_present_wait: bool = false,
};

const SwapchainData = struct {
    device: VkDevice,
    swapchain: VkSwapchainKHR,
    width: u32,
    height: u32,
    format: VkFormat,
    present_mode: VkPresentModeKHR,
    frame_count: u64 = 0,
    last_present_ns: u64 = 0,
    // VK_NV_low_latency2 state
    low_latency_enabled: bool = false,
    low_latency_boost: bool = false,
    current_present_id: u64 = 0,
    // Frame timing from Reflex
    last_sim_start_ns: u64 = 0,
    last_render_submit_ns: u64 = 0,
    last_gpu_render_ns: u64 = 0,
};

// Static storage for layer data (limited to 4 instances, 8 devices, 16 swapchains)
var instances: [4]?InstanceData = .{ null, null, null, null };
var devices: [8]?DeviceData = .{ null, null, null, null, null, null, null, null };
var swapchains: [16]?SwapchainData = .{null} ** 16;

// Frame timing statistics
var total_frames: u64 = 0;
var avg_frame_time_ns: u64 = 0;
var last_log_time_ns: u64 = 0;

// Latency tracking (rolling buffer for stats)
const LatencySample = struct {
    frame_id: u64 = 0,
    sim_to_present_us: u64 = 0,
    gpu_render_us: u64 = 0,
    total_latency_us: u64 = 0,
};

const LATENCY_BUFFER_SIZE = 120; // ~2 seconds at 60fps
var latency_samples: [LATENCY_BUFFER_SIZE]LatencySample = [_]LatencySample{.{}} ** LATENCY_BUFFER_SIZE;
var latency_index: usize = 0;
var latency_count: usize = 0;
var latency_sum_us: u64 = 0;
var latency_gpu_sum_us: u64 = 0;

fn recordLatencySample(sample: LatencySample) void {
    // Remove old sample from sums if buffer is full
    if (latency_count == LATENCY_BUFFER_SIZE) {
        const old = latency_samples[latency_index];
        if (latency_sum_us >= old.sim_to_present_us) {
            latency_sum_us -= old.sim_to_present_us;
        }
        if (latency_gpu_sum_us >= old.gpu_render_us) {
            latency_gpu_sum_us -= old.gpu_render_us;
        }
    }

    // Store new sample
    latency_samples[latency_index] = sample;
    latency_sum_us += sample.sim_to_present_us;
    latency_gpu_sum_us += sample.gpu_render_us;

    latency_index = (latency_index + 1) % LATENCY_BUFFER_SIZE;
    if (latency_count < LATENCY_BUFFER_SIZE) latency_count += 1;
}

fn getAverageLatencyMs() f32 {
    if (latency_count == 0) return 0;
    const avg_us: f32 = @floatFromInt(latency_sum_us / latency_count);
    return avg_us / 1000.0;
}

fn getAverageGpuMs() f32 {
    if (latency_count == 0) return 0;
    const avg_us: f32 = @floatFromInt(latency_gpu_sum_us / latency_count);
    return avg_us / 1000.0;
}

// ============================================================================
// Utility Functions
// ============================================================================

fn getCurrentTimeNs() u64 {
    const now = std.time.Instant.now() catch return 0;
    const sec: u64 = @intCast(now.timestamp.sec);
    const nsec: u64 = @intCast(now.timestamp.nsec);
    return sec * 1_000_000_000 + nsec;
}

fn findInstance(instance: VkInstance) ?*InstanceData {
    for (&instances) |*slot| {
        if (slot.*) |*data| {
            if (data.instance == instance) return data;
        }
    }
    return null;
}

fn findDevice(device: VkDevice) ?*DeviceData {
    for (&devices) |*slot| {
        if (slot.*) |*data| {
            if (data.device == device) return data;
        }
    }
    return null;
}

fn findSwapchain(swapchain: VkSwapchainKHR) ?*SwapchainData {
    for (&swapchains) |*slot| {
        if (slot.*) |*data| {
            if (data.swapchain == swapchain) return data;
        }
    }
    return null;
}

fn storeInstance(data: InstanceData) bool {
    for (&instances) |*slot| {
        if (slot.* == null) {
            slot.* = data;
            return true;
        }
    }
    return false;
}

fn storeDevice(data: DeviceData) bool {
    for (&devices) |*slot| {
        if (slot.* == null) {
            slot.* = data;
            return true;
        }
    }
    return false;
}

fn storeSwapchain(data: SwapchainData) bool {
    for (&swapchains) |*slot| {
        if (slot.* == null) {
            slot.* = data;
            return true;
        }
    }
    return false;
}

fn removeInstance(instance: VkInstance) void {
    for (&instances) |*slot| {
        if (slot.*) |data| {
            if (data.instance == instance) {
                slot.* = null;
                return;
            }
        }
    }
}

fn removeDevice(device: VkDevice) void {
    for (&devices) |*slot| {
        if (slot.*) |data| {
            if (data.device == device) {
                slot.* = null;
                return;
            }
        }
    }
}

fn removeSwapchain(swapchain: VkSwapchainKHR) void {
    for (&swapchains) |*slot| {
        if (slot.*) |data| {
            if (data.swapchain == swapchain) {
                slot.* = null;
                return;
            }
        }
    }
}

fn getLayerInstanceLink(create_info: *const VkInstanceCreateInfo) ?struct { link: *VkLayerInstanceLink, info: *VkLayerInstanceCreateInfo } {
    var p: ?*const anyopaque = create_info.pNext;
    while (p != null) {
        // Cast away const to allow chain advancement (required by Vulkan layer spec)
        const info: *VkLayerInstanceCreateInfo = @ptrCast(@alignCast(@constCast(p)));
        if (info.sType == VK_STRUCTURE_TYPE_LOADER_INSTANCE_CREATE_INFO and
            info.function == VK_LAYER_LINK_INFO)
        {
            return .{ .link = info.u.pLayerInfo, .info = info };
        }
        p = info.pNext;
    }
    return null;
}

fn getLayerDeviceLink(create_info: *const VkDeviceCreateInfo) ?struct { link: *VkLayerDeviceLink, info: *VkLayerDeviceCreateInfo } {
    var p: ?*const anyopaque = create_info.pNext;
    while (p != null) {
        // Cast away const to allow chain advancement (required by Vulkan layer spec)
        const info: *VkLayerDeviceCreateInfo = @ptrCast(@alignCast(@constCast(p)));
        if (info.sType == VK_STRUCTURE_TYPE_LOADER_DEVICE_CREATE_INFO and
            info.function == VK_LAYER_LINK_INFO)
        {
            return .{ .link = info.u.pLayerInfo, .info = info };
        }
        p = info.pNext;
    }
    return null;
}

// ============================================================================
// Layer Intercepts
// ============================================================================

fn venom_vkCreateInstance(
    create_info: *const VkInstanceCreateInfo,
    allocator_ptr: ?*const VkAllocationCallbacks,
    instance_ptr: *VkInstance,
) callconv(.c) VkResult {
    // Get chain info
    const chain = getLayerInstanceLink(create_info) orelse return .error_initialization_failed;

    // Get next layer's vkGetInstanceProcAddr
    const next_gipa = chain.link.pfnNextGetInstanceProcAddr;

    // Advance chain for next layer (consume our entry)
    // pNext may be null if we're the last layer before the ICD
    if (chain.link.pNext) |next| {
        chain.info.u.pLayerInfo = next;
    }

    // Get vkCreateInstance from next layer
    const create_instance_fn: ?PFN_vkCreateInstance = @ptrCast(next_gipa(null, "vkCreateInstance"));
    if (create_instance_fn == null) return .error_initialization_failed;

    // Call next layer's vkCreateInstance
    const result = create_instance_fn.?(create_info, allocator_ptr, instance_ptr);
    if (result != .success) return result;

    // Store instance data
    const destroy_fn: ?PFN_vkDestroyInstance = @ptrCast(next_gipa(instance_ptr.*, "vkDestroyInstance"));

    _ = storeInstance(.{
        .instance = instance_ptr.*,
        .next_gipa = next_gipa,
        .next_destroy_instance = destroy_fn,
    });

    // Log layer activation
    std.debug.print("[VENOM] Instance created\n", .{});

    return .success;
}

fn venom_vkDestroyInstance(
    instance: VkInstance,
    allocator_ptr: ?*const VkAllocationCallbacks,
) callconv(.c) void {
    if (findInstance(instance)) |data| {
        if (data.next_destroy_instance) |destroy| {
            destroy(instance, allocator_ptr);
        }
        removeInstance(instance);
    }
}

fn venom_vkCreateDevice(
    physical_device: VkPhysicalDevice,
    create_info: *const VkDeviceCreateInfo,
    allocator_ptr: ?*const VkAllocationCallbacks,
    device_ptr: *VkDevice,
) callconv(.c) VkResult {
    // Get chain info
    const chain = getLayerDeviceLink(create_info) orelse return .error_initialization_failed;

    const next_gipa = chain.link.pfnNextGetInstanceProcAddr;
    const next_gdpa = chain.link.pfnNextGetDeviceProcAddr;

    // Advance chain (consume our entry)
    // pNext may be null if we're the last layer before the ICD
    if (chain.link.pNext) |next| {
        chain.info.u.pLayerInfo = next;
    }

    // Get vkCreateDevice from instance
    const create_device_fn: ?PFN_vkCreateDevice = @ptrCast(next_gipa(null, "vkCreateDevice"));
    if (create_device_fn == null) return .error_initialization_failed;

    // Call next layer
    const result = create_device_fn.?(physical_device, create_info, allocator_ptr, device_ptr);
    if (result != .success) return result;

    const device = device_ptr.*;

    // Get function pointers for device-level functions
    const destroy_device: ?PFN_vkDestroyDevice = @ptrCast(next_gdpa(device, "vkDestroyDevice"));
    const create_swapchain: ?PFN_vkCreateSwapchainKHR = @ptrCast(next_gdpa(device, "vkCreateSwapchainKHR"));
    const destroy_swapchain: ?PFN_vkDestroySwapchainKHR = @ptrCast(next_gdpa(device, "vkDestroySwapchainKHR"));
    const queue_present: ?PFN_vkQueuePresentKHR = @ptrCast(next_gdpa(device, "vkQueuePresentKHR"));

    // Probe for VK_NV_low_latency2 functions
    const set_latency_sleep_mode: ?PFN_vkSetLatencySleepModeNV = @ptrCast(next_gdpa(device, "vkSetLatencySleepModeNV"));
    const latency_sleep: ?PFN_vkLatencySleepNV = @ptrCast(next_gdpa(device, "vkLatencySleepNV"));
    const set_latency_marker: ?PFN_vkSetLatencyMarkerNV = @ptrCast(next_gdpa(device, "vkSetLatencyMarkerNV"));
    const get_latency_timings: ?PFN_vkGetLatencyTimingsNV = @ptrCast(next_gdpa(device, "vkGetLatencyTimingsNV"));
    const queue_notify_oob: ?PFN_vkQueueNotifyOutOfBandNV = @ptrCast(next_gdpa(device, "vkQueueNotifyOutOfBandNV"));

    const has_low_latency2 = set_latency_sleep_mode != null;

    // Probe for VK_KHR_present_wait
    const wait_for_present: ?PFN_vkWaitForPresentKHR = @ptrCast(next_gdpa(device, "vkWaitForPresentKHR"));
    const has_present_wait = wait_for_present != null;

    _ = storeDevice(.{
        .device = device,
        .instance = null,
        .next_gdpa = next_gdpa,
        .next_destroy_device = destroy_device,
        .next_create_swapchain = create_swapchain,
        .next_destroy_swapchain = destroy_swapchain,
        .next_queue_present = queue_present,
        .next_set_latency_sleep_mode = set_latency_sleep_mode,
        .next_latency_sleep = latency_sleep,
        .next_set_latency_marker = set_latency_marker,
        .next_get_latency_timings = get_latency_timings,
        .next_queue_notify_oob = queue_notify_oob,
        .next_wait_for_present = wait_for_present,
        .has_low_latency2 = has_low_latency2,
        .has_present_wait = has_present_wait,
    });

    std.debug.print("[VENOM] Device created (low_latency2={}, present_wait={})\n", .{ has_low_latency2, has_present_wait });

    return .success;
}

fn venom_vkDestroyDevice(
    device: VkDevice,
    allocator_ptr: ?*const VkAllocationCallbacks,
) callconv(.c) void {
    if (findDevice(device)) |data| {
        if (data.next_destroy_device) |destroy| {
            destroy(device, allocator_ptr);
        }
        removeDevice(device);
    }
}

fn venom_vkCreateSwapchainKHR(
    device: VkDevice,
    create_info: *const VkSwapchainCreateInfoKHR,
    allocator_ptr: ?*const VkAllocationCallbacks,
    swapchain_ptr: *VkSwapchainKHR,
) callconv(.c) VkResult {
    const device_data = findDevice(device) orelse return .error_device_lost;
    const next_fn = device_data.next_create_swapchain orelse return .error_initialization_failed;

    const result = next_fn(device, create_info, allocator_ptr, swapchain_ptr);
    if (result != .success) return result;

    // Store swapchain info
    _ = storeSwapchain(.{
        .device = device,
        .swapchain = swapchain_ptr.*,
        .width = create_info.imageExtent.width,
        .height = create_info.imageExtent.height,
        .format = create_info.imageFormat,
        .present_mode = create_info.presentMode,
    });

    std.debug.print("[VENOM] Swapchain created {}x{} mode={}\n", .{
        create_info.imageExtent.width,
        create_info.imageExtent.height,
        @intFromEnum(create_info.presentMode),
    });

    return .success;
}

fn venom_vkDestroySwapchainKHR(
    device: VkDevice,
    swapchain: VkSwapchainKHR,
    allocator_ptr: ?*const VkAllocationCallbacks,
) callconv(.c) void {
    if (findDevice(device)) |data| {
        if (data.next_destroy_swapchain) |destroy| {
            destroy(device, swapchain, allocator_ptr);
        }
    }
    removeSwapchain(swapchain);
}

fn venom_vkQueuePresentKHR(
    queue: VkQueue,
    present_info: *const VkPresentInfoKHR,
) callconv(.c) VkResult {
    const now = getCurrentTimeNs();

    // Track frame timing for each swapchain
    if (present_info.pSwapchains) |swapchain_array| {
        var i: u32 = 0;
        while (i < present_info.swapchainCount) : (i += 1) {
            if (findSwapchain(swapchain_array[i])) |sc| {
                if (sc.last_present_ns > 0) {
                    const frame_time = now - sc.last_present_ns;

                    // Update rolling average (EMA with alpha=0.1)
                    if (avg_frame_time_ns == 0) {
                        avg_frame_time_ns = frame_time;
                    } else {
                        avg_frame_time_ns = (avg_frame_time_ns * 9 + frame_time) / 10;
                    }
                }
                sc.last_present_ns = now;
                sc.frame_count += 1;
                total_frames += 1;
            }
        }
    }

    // Log stats every 5 seconds
    if (now - last_log_time_ns > 5_000_000_000) {
        const fps = if (avg_frame_time_ns > 0) @divTrunc(@as(u64, 1_000_000_000), avg_frame_time_ns) else 0;
        const avg_latency = getAverageLatencyMs();
        const avg_gpu = getAverageGpuMs();
        std.debug.print("[VENOM] {} frames, ~{} FPS, {d:.2}ms frame | latency: {d:.1}ms, GPU: {d:.1}ms\n", .{
            total_frames,
            fps,
            @as(f64, @floatFromInt(avg_frame_time_ns)) / 1_000_000.0,
            avg_latency,
            avg_gpu,
        });
        last_log_time_ns = now;
    }

    // Find device data to get next function
    // We need to find which device this queue belongs to
    for (&devices) |*slot| {
        if (slot.*) |*data| {
            if (data.next_queue_present) |present| {
                return present(queue, present_info);
            }
        }
    }

    return .error_device_lost;
}

// ============================================================================
// VK_NV_low_latency2 Intercepts
// ============================================================================

fn venom_vkSetLatencySleepModeNV(
    device: VkDevice,
    swapchain: VkSwapchainKHR,
    sleep_mode_info: *const VkLatencySleepModeInfoNV,
) callconv(.c) VkResult {
    const device_data = findDevice(device) orelse return .error_device_lost;

    // Track latency mode state
    if (findSwapchain(swapchain)) |sc| {
        sc.low_latency_enabled = sleep_mode_info.lowLatencyMode != 0;
        sc.low_latency_boost = sleep_mode_info.lowLatencyBoost != 0;

        std.debug.print("[VENOM] SetLatencySleepMode enabled={} boost={} interval={}us\n", .{
            sc.low_latency_enabled,
            sc.low_latency_boost,
            sleep_mode_info.minimumIntervalUs,
        });
    }

    // Pass through to driver
    if (device_data.next_set_latency_sleep_mode) |next| {
        return next(device, swapchain, sleep_mode_info);
    }
    return .error_extension_not_present;
}

fn venom_vkLatencySleepNV(
    device: VkDevice,
    swapchain: VkSwapchainKHR,
    sleep_info: *const VkLatencySleepInfoNV,
) callconv(.c) VkResult {
    const device_data = findDevice(device) orelse return .error_device_lost;

    // Pass through to driver - this is where Reflex actually sleeps
    if (device_data.next_latency_sleep) |next| {
        return next(device, swapchain, sleep_info);
    }
    return .error_extension_not_present;
}

fn venom_vkSetLatencyMarkerNV(
    device: VkDevice,
    swapchain: VkSwapchainKHR,
    marker_info: *const VkSetLatencyMarkerInfoNV,
) callconv(.c) void {
    const device_data = findDevice(device) orelse return;
    const now = getCurrentTimeNs();

    // Track marker timing
    if (findSwapchain(swapchain)) |sc| {
        sc.current_present_id = marker_info.presentID;

        switch (marker_info.marker) {
            .simulation_start => {
                sc.last_sim_start_ns = now;
            },
            .rendersubmit_start => {
                sc.last_render_submit_ns = now;
            },
            .present_start => {
                // Calculate sim-to-present latency and record it
                if (sc.last_sim_start_ns > 0) {
                    const latency_us = (now - sc.last_sim_start_ns) / 1000;
                    recordLatencySample(.{
                        .frame_id = sc.current_present_id,
                        .sim_to_present_us = latency_us,
                        .gpu_render_us = sc.last_gpu_render_ns / 1000,
                        .total_latency_us = latency_us,
                    });
                }
            },
            else => {},
        }
    }

    // Pass through to driver
    if (device_data.next_set_latency_marker) |next| {
        next(device, swapchain, marker_info);
    }
}

fn venom_vkGetLatencyTimingsNV(
    device: VkDevice,
    swapchain: VkSwapchainKHR,
    latency_marker_info: *VkGetLatencyMarkerInfoNV,
) callconv(.c) void {
    const device_data = findDevice(device) orelse return;

    // Pass through to driver to get actual GPU timings
    if (device_data.next_get_latency_timings) |next| {
        next(device, swapchain, latency_marker_info);
    }

    // Process timing data and feed to latency engine
    if (latency_marker_info.pTimings) |timings| {
        if (latency_marker_info.timingCount > 0) {
            const t = timings[0];
            if (t.presentID > 0) {
                const gpu_time_us = if (t.gpuRenderEndTimeUs > t.gpuRenderStartTimeUs)
                    t.gpuRenderEndTimeUs - t.gpuRenderStartTimeUs
                else
                    0;
                const total_us = if (t.presentEndTimeUs > t.simStartTimeUs)
                    t.presentEndTimeUs - t.simStartTimeUs
                else
                    0;

                // Update swapchain GPU timing for next present marker
                if (findSwapchain(swapchain)) |sc| {
                    sc.last_gpu_render_ns = gpu_time_us * 1000;
                }

                // Record accurate timing from driver
                if (total_us > 0) {
                    recordLatencySample(.{
                        .frame_id = t.presentID,
                        .sim_to_present_us = total_us,
                        .gpu_render_us = gpu_time_us,
                        .total_latency_us = total_us,
                    });
                }
            }
        }
    }
}

fn venom_vkQueueNotifyOutOfBandNV(
    queue: VkQueue,
    queue_type_info: *const VkOutOfBandQueueTypeInfoNV,
) callconv(.c) void {
    // Pass through - out-of-band notification for better scheduling
    for (&devices) |*slot| {
        if (slot.*) |*data| {
            if (data.next_queue_notify_oob) |next| {
                next(queue, queue_type_info);
                return;
            }
        }
    }
}

fn venom_vkWaitForPresentKHR(
    device: VkDevice,
    swapchain: VkSwapchainKHR,
    present_id: u64,
    timeout: u64,
) callconv(.c) VkResult {
    const device_data = findDevice(device) orelse return .error_device_lost;

    // Pass through to driver
    if (device_data.next_wait_for_present) |next| {
        return next(device, swapchain, present_id, timeout);
    }
    return .error_extension_not_present;
}

// ============================================================================
// Exported Entry Points
// ============================================================================

export fn venom_vkGetInstanceProcAddr(instance: VkInstance, name: [*:0]const u8) PFN_vkVoidFunction {
    const name_slice = std.mem.span(name);

    // Layer intercepts
    if (std.mem.eql(u8, name_slice, "vkCreateInstance")) {
        return @ptrCast(&venom_vkCreateInstance);
    }
    if (std.mem.eql(u8, name_slice, "vkDestroyInstance")) {
        return @ptrCast(&venom_vkDestroyInstance);
    }
    if (std.mem.eql(u8, name_slice, "vkCreateDevice")) {
        return @ptrCast(&venom_vkCreateDevice);
    }
    if (std.mem.eql(u8, name_slice, "vkGetInstanceProcAddr")) {
        return @ptrCast(&venom_vkGetInstanceProcAddr);
    }

    // Pass through to next layer
    if (findInstance(instance)) |data| {
        return data.next_gipa(instance, name);
    }

    return null;
}

export fn venom_vkGetDeviceProcAddr(device: VkDevice, name: [*:0]const u8) PFN_vkVoidFunction {
    const name_slice = std.mem.span(name);

    // Device-level intercepts
    if (std.mem.eql(u8, name_slice, "vkDestroyDevice")) {
        return @ptrCast(&venom_vkDestroyDevice);
    }
    if (std.mem.eql(u8, name_slice, "vkCreateSwapchainKHR")) {
        return @ptrCast(&venom_vkCreateSwapchainKHR);
    }
    if (std.mem.eql(u8, name_slice, "vkDestroySwapchainKHR")) {
        return @ptrCast(&venom_vkDestroySwapchainKHR);
    }
    if (std.mem.eql(u8, name_slice, "vkQueuePresentKHR")) {
        return @ptrCast(&venom_vkQueuePresentKHR);
    }
    if (std.mem.eql(u8, name_slice, "vkGetDeviceProcAddr")) {
        return @ptrCast(&venom_vkGetDeviceProcAddr);
    }

    // VK_NV_low_latency2 intercepts
    if (std.mem.eql(u8, name_slice, "vkSetLatencySleepModeNV")) {
        return @ptrCast(&venom_vkSetLatencySleepModeNV);
    }
    if (std.mem.eql(u8, name_slice, "vkLatencySleepNV")) {
        return @ptrCast(&venom_vkLatencySleepNV);
    }
    if (std.mem.eql(u8, name_slice, "vkSetLatencyMarkerNV")) {
        return @ptrCast(&venom_vkSetLatencyMarkerNV);
    }
    if (std.mem.eql(u8, name_slice, "vkGetLatencyTimingsNV")) {
        return @ptrCast(&venom_vkGetLatencyTimingsNV);
    }
    if (std.mem.eql(u8, name_slice, "vkQueueNotifyOutOfBandNV")) {
        return @ptrCast(&venom_vkQueueNotifyOutOfBandNV);
    }

    // VK_KHR_present_wait intercept
    if (std.mem.eql(u8, name_slice, "vkWaitForPresentKHR")) {
        return @ptrCast(&venom_vkWaitForPresentKHR);
    }

    // Pass through to next layer
    if (findDevice(device)) |data| {
        return data.next_gdpa(device, name);
    }

    return null;
}

// Also export as vkGetInstanceProcAddr/vkGetDeviceProcAddr for direct loading
export fn vkGetInstanceProcAddr(instance: VkInstance, name: [*:0]const u8) PFN_vkVoidFunction {
    return venom_vkGetInstanceProcAddr(instance, name);
}

export fn vkGetDeviceProcAddr(device: VkDevice, name: [*:0]const u8) PFN_vkVoidFunction {
    return venom_vkGetDeviceProcAddr(device, name);
}

// ============================================================================
// Latency Query API (for other venom components)
// ============================================================================

/// Latency statistics structure for C interop
pub const VenomLatencyStats = extern struct {
    avg_latency_ms: f32,
    avg_gpu_ms: f32,
    frame_count: u64,
    sample_count: u32,
};

/// Get current latency statistics
export fn venom_get_latency_stats() VenomLatencyStats {
    return .{
        .avg_latency_ms = getAverageLatencyMs(),
        .avg_gpu_ms = getAverageGpuMs(),
        .frame_count = total_frames,
        .sample_count = @intCast(latency_count),
    };
}

/// Get average latency in milliseconds
export fn venom_get_avg_latency_ms() f32 {
    return getAverageLatencyMs();
}

/// Get average GPU render time in milliseconds
export fn venom_get_avg_gpu_ms() f32 {
    return getAverageGpuMs();
}

/// Get total frame count
export fn venom_get_frame_count() u64 {
    return total_frames;
}

// ============================================================================
// Tests
// ============================================================================

test "layer compiles" {
    _ = getCurrentTimeNs();
}
