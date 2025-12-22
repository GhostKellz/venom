# VENOM Development Container
# Arch Linux with wlroots + NVIDIA for compositor testing

FROM archlinux:latest

# Update and install dependencies
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm \
    base-devel \
    git \
    curl \
    wlroots0.17 \
    wayland \
    wayland-protocols \
    libdrm \
    mesa \
    vulkan-icd-loader \
    vulkan-tools \
    nvidia-utils \
    cuda \
    libxkbcommon \
    pixman \
    libinput \
    seatd \
    xorg-xwayland \
    foot \
    weston \
    && pacman -Scc --noconfirm

# Zig will be mounted from host at /opt/zig-0.16.0-dev
# Link to /usr/local/bin for convenience
RUN ln -sf /opt/zig-0.16.0-dev/zig /usr/local/bin/zig

# Set up working directory
WORKDIR /workspace

# Environment
ENV XDG_RUNTIME_DIR=/tmp/runtime
ENV WAYLAND_DISPLAY=wayland-0

# Create runtime directory
RUN mkdir -p /tmp/runtime && chmod 700 /tmp/runtime

CMD ["/bin/bash"]
