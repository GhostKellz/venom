# VENOM

**NVIDIA-Native Gaming Runtime for Linux**

VENOM is a high-performance gaming runtime and compositor designed as the "Gamescope killer" — built from the ground up for NVIDIA GPUs with deep integration into the NVPrime ecosystem.

## Vision

```
┌─────────────────────────────────────────────────────────────┐
│                      Games / Steam / Proton                  │
├─────────────────────────────────────────────────────────────┤
│                          VENOM                               │
│         (Gaming Runtime, Compositor, Latency Engine)         │
├─────────────────────────────────────────────────────────────┤
│                     NVPrime Platform                         │
│    (nvlatency, nvsync, nvhud, nvvk, nvcore, nvpower)        │
├─────────────────────────────────────────────────────────────┤
│                    NVIDIA Driver / DRM                       │
└─────────────────────────────────────────────────────────────┘
```

## What VENOM Is

VENOM is **NOT** an overlay. VENOM is **NOT** a driver.

VENOM is a **full gaming layer** that sits between the OS and games:

- **Gaming Compositor** — Wayland-based, NVIDIA-optimized (via PrimeTime)
- **Latency Engine** — Reflex-style frame queue control and input timing
- **Runtime Shell** — Launches games with optimal NVIDIA settings
- **Vulkan Layer** — Zero-copy overlays, shader introspection, frame hooks

## Features

### Core Runtime
- Frame scheduling and pacing
- Direct scanout support
- VRR/G-Sync coordination
- Low-latency input pipeline
- Automatic NVIDIA env var injection

### Compositor (via PrimeTime)
- wlroots-based Wayland compositor
- HDR passthrough
- Variable refresh rate control
- Frame limiter (GPU-level, zero input lag)
- FSR/NIS upscaling support

### Latency Engine
- Full latency pipeline tracking (input → display)
- Reflex-compatible latency markers
- Frame queue depth control
- Latency prediction

### Vulkan Layer
- Frame timing hooks
- Swapchain introspection
- Zero-copy overlay support
- Works with native Vulkan, DXVK, vkd3d-proton

## Usage

### CLI

```bash
# Run a game through VENOM
venom run ./game

# Run with options
venom run --fps=144 --no-vrr ./game

# Run Steam game
venom run steam steam://rungameid/1234

# Show system info
venom info

# Show version
venom version
```

### Options

| Option | Description |
|--------|-------------|
| `--fps=<N>` | Limit framerate to N FPS |
| `--no-vrr` | Disable VRR (G-Sync/FreeSync) |
| `--no-hdr` | Disable HDR passthrough |
| `--low-latency` | Enable low-latency mode (default) |
| `--hud` | Show performance overlay |

### Environment Variables

```bash
# Enable VENOM for Steam
VENOM_ENABLED=1 %command%

# Configure options via env
VENOM_FPS_LIMIT=144
VENOM_VRR=1
VENOM_LOW_LATENCY=1
```

## Architecture

```
VENOM
├── src/
│   ├── root.zig          # Core Venom struct, config, subsystem init
│   ├── main.zig          # CLI interface
│   ├── runtime.zig       # Frame scheduling, game process management
│   ├── latency.zig       # Reflex-style latency engine
│   ├── compositor.zig    # Wayland compositor context
│   └── vulkan_layer.zig  # Vulkan layer for game injection
```

### Subsystems

| Module | Purpose |
|--------|---------|
| **runtime** | Frame timing, game spawning, NVIDIA env setup |
| **latency** | Latency sampling, prediction, queue control |
| **compositor** | Wayland compositor (wraps PrimeTime) |
| **vulkan_layer** | In-game hooks, overlay, timing markers |

## Building

```bash
# Build
zig build

# Build optimized
zig build -Doptimize=ReleaseFast

# Run tests
zig build test

# Run CLI
./zig-out/bin/venom --help
```

## Vulkan Layer

VENOM includes an implicit Vulkan layer for frame timing and VK_NV_low_latency2 integration.

```bash
# Enable VENOM layer for a game
VK_ADD_IMPLICIT_LAYER_PATH=/path/to/venom/zig-out/share/vulkan/implicit_layer.d \
VENOM_LAYER=1 ./game

# Or install system-wide
sudo cp zig-out/share/vulkan/implicit_layer.d/*.json /etc/vulkan/implicit_layer.d/
sudo cp zig-out/lib/libvenom_layer.so /usr/lib/

# Then just use VENOM_LAYER=1
VENOM_LAYER=1 ./game
```

Layer features:
- Frame timing with FPS stats (logged every 5 seconds)
- Swapchain introspection (resolution, present mode)
- VK_NV_low_latency2 passthrough and monitoring
- VK_KHR_present_wait support
- Vulkan 1.4 compatible

## Requirements

- NVIDIA GPU (Turing or newer recommended for full features)
- NVIDIA Open driver 590+ with GSP=1 (590.48.01 recommended)
- Linux 6.x+ (6.12+ with CachyOS/EEVDF for best latency)
- Zig 0.16+
- Vulkan 1.3+

## Integration with NVPrime Stack

| Project | Integration |
|---------|-------------|
| **nvprime** | GPU caps, power, display queries |
| **nvlatency** | Reflex latency markers and control |
| **nvsync** | VRR/G-Sync management |
| **nvhud** | Performance overlay |
| **nvvk** | Vulkan NVIDIA extensions |
| **nvproton** | Proton game launching |

## Goals

| Metric | Target |
|--------|--------|
| Latency | Lower than Gamescope |
| Overhead | < 1ms compositor |
| GPU overhead | < 1% |
| Input delay | Near-native |
| Compatibility | All Proton / native Vulkan |

## Roadmap

- [x] Project scaffold
- [x] Core runtime structure
- [x] Latency engine scaffold
- [x] Vulkan layer scaffold
- [x] CLI interface
- [x] Wire up nvprime integration
- [x] Vulkan layer implementation (frame timing, swapchain, VK_NV_low_latency2)
- [ ] Wire up nvsync/nvlatency hooks
- [ ] PrimeTime compositor integration
- [ ] nvhud overlay integration
- [ ] Steam/Proton launch wrapper

## License

MIT License - See [LICENSE](LICENSE)

---

*VENOM — Inject Performance*
