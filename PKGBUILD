# Maintainer: GhostKellz <ghost@ghostkellz.sh>
pkgname=venom
pkgver=1.0.0
pkgrel=1
pkgdesc="Gaming Runtime for Linux - Vulkan layer with Reflex and frame timing"
arch=('x86_64')
url="https://github.com/ghostkellz/venom"
license=('MIT')
depends=('glibc' 'vulkan-icd-loader')
makedepends=('zig>=0.14')
optdepends=(
    'nvidia-utils: NVIDIA GPU detection'
    'nvprime: GPU metrics integration'
)
provides=('venom')
install=venom.install
source=("$pkgname-$pkgver.tar.gz::$url/archive/v$pkgver.tar.gz")
sha256sums=('SKIP')

build() {
    cd "$pkgname-$pkgver"
    zig build -Doptimize=ReleaseFast
}

package() {
    cd "$pkgname-$pkgver"

    # CLI binary
    install -Dm755 zig-out/bin/venom "$pkgdir/usr/bin/venom"

    # Vulkan layer library
    install -Dm755 zig-out/lib/libVkLayer_venom.so "$pkgdir/usr/lib/libVkLayer_venom.so"

    # Layer manifest (implicit layer - loads when VENOM_LAYER=1)
    install -Dm644 zig-out/share/vulkan/implicit_layer.d/venom_layer.json \
        "$pkgdir/usr/share/vulkan/implicit_layer.d/venom_layer.json"

    # Documentation
    install -Dm644 README.md "$pkgdir/usr/share/doc/$pkgname/README.md"
    install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
