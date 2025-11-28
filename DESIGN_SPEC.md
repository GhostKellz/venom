# 🐍 VENOM — High-Performance Gaming Runtime & Compositor

**VENOM** is a next-generation Linux gaming runtime and compositor built on top of your
NVPrime stack. It is designed to be the **Gamescope killer**, NVIDIA-native,
latency-focused, and performance-first.

VENOM is NOT an overlay.  
VENOM is NOT a driver.  
VENOM is a **full gaming layer** designed to sit between the OS and games.

---

## Vision

VENOM is the **killer runtime layer for NVIDIA gaming on Linux**.

Think:

- Gamescope  
- SteamOS compositor  
- NVIDIA control / pipeline layer  
- Low latency infrastructure  
- Unified capture + stream + overlay stack  

All in **one cohesive platform**.

---

## High-Level Architecture

VENOM sits on top of **NVPrime** and integrates:

Game → VENOM → NVPrime → NVIDIA Driver → GPU


Subsidiary integrations:

- nvhud (overlay)
- nvstream (streaming)
- nvlatency (reflex / latency data)
- nvdisplay (VRR, HDR)
- nvcore / nvpower (clocks, thermals)
- nvcomposit (Wayland compositor)
- GhostKernel (kernel optimizations)
- nvcontrol (GUI frontend)

---

## Core Components

### 🧠 VENOM Runtime
Handles:
- Frame scheduling
- Latency control
- Direct scanout
- Frame pacing
- Input timing

### 🖥️ VENOM Compositor
Wayland-based or hybrid compositor:
- Game-only mode
- Overlay support
- HDR passthrough
- Direct VRR control
- Frame limiter

### 🎯 VENOM Latency Engine
Deep NVIDIA integration:
- Reflex monitoring
- Frame queue analysis
- GPU scheduling hooks
- Custom latency graphs

### 🎮 VENOM Game Injection Layer
Works with:
- Vulkan
- DXVK
- vkd3d-proton
- OpenGL

Allows:
- Zero-copy overlays
- VRR manipulation
- Frame prediction
- Shader pipeline introspection

---

## Goals

| Feature | Target |
|------|------|
| Latency | Lower than Gamescope |
| Overhead | < 1ms |
| GPU overhead | < 1% |
| Input delay | Near-native |
| Frame stability | Superior smoothness |
| Compatibility | All Proton / native Vulkan |

---

## Subsystems

### 1. VENOMHUD (Powered by nvhud)
- Replaces MangoHud
- Full NVIDIA telemetry
- Frame pacing graphs
- Shader compile live status
- DLSS/Reflex indicators

### 2. VENOMSTREAM
- NVIDIA-native game streaming layer
- Moonlight compatible
- Low latency local streaming
- OBS integration via plugin API

### 3. VENOMCONTROL
User configuration GUI:
- Game profiles
- Latency tuning
- VRR control
- Resolution scaling
- Injection pipeline management

---

## Language & Tech Stack

| Component | Language |
|--------|---------|
| Core runtime | Zig |
| Vulkan layer | Zig |
| Overlay / HUD | Zig |
| GUI (config) | Rust |
| Low-level hooks | C + Zig |
| API bindings | Rust + Python |

---

## Roadmap

### Phase 1: Foundation
- Runtime skeleton
- Vulkan layer hooks
- Basic window handling

### Phase 2: Compositor
- Wayland compositor base
- HDR passthrough
- Direct scanout mode

### Phase 3: Overlay & HUD
- Integrate nvhud
- Metrics + telemetry
- Benchmark engine

### Phase 4: Latency Stack
- Reflex integration
- Queue manipulation
- Frame prediction

### Phase 5: Streaming
- NVENC pipeline
- Network implementation
- Moonlight compatibility

### Phase 6: Production
- Packaging
- Flatpak/AUR
- Documentation
- Marketing push

---

## Branding Direction

VENOM is positioned as:

> The NVIDIA-native gaming runtime for Linux power users.

Slogan ideas:
- "VENOM — Inject Performance"
- "VENOM — Where Linux Games Dominate"
- "VENOM — No Lag. No Limits."

---

## Long-Term Vision

VENOM evolves into:

- A SteamOS alternative gaming core
- Standard runtime for NVIDIA Linux
- Primary gaming stack for GhostKernel
- Future base layer for GhostOS

---

© GhostKellz 2025 — Experimental Research Platform

