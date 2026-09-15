#!/bin/bash
set -euo pipefail

# ---- Defaults ----
WINE_FOLDER="11.0"
WINE_VERSION="11.0"
MODE="install"
PREFIX=""
BUILD_DIR=""
OUTPUT_DIR=""

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --folder FOLDER     Source folder on dl.winehq.org (e.g., 11.0 or 11.x). Default: 11.0
  --version VERSION   Wine version / filename version (e.g., 11.0 or 11.17). Default: 11.0
  --mode MODE         'install' (default) or 'rpm'
  --prefix PREFIX     Install prefix (install mode). Default: /opt/wine-<major>
  --build-dir DIR     Build/download directory. Default: /var/tmp/wine-build-<version>
  --output-dir DIR    Where to place built RPMs (rpm mode). Default: ./dist
  -h, --help          Show this help
EOF
    exit 0
}

# ---- Parse args ----
while [[ $# -gt 0 ]]; do
    case "$1" in
        --folder)     WINE_FOLDER="$2"; shift 2 ;;
        --version)    WINE_VERSION="$2"; shift 2 ;;
        --mode)       MODE="$2"; shift 2 ;;
        --prefix)     PREFIX="$2"; shift 2 ;;
        --build-dir)  BUILD_DIR="$2"; shift 2 ;;
        --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        -h|--help)    usage ;;
        *) echo "Unknown option: $1" >&2; usage ;;
    esac
done

case "$MODE" in
    install|rpm) ;;
    *) echo "Invalid mode: $MODE (must be 'install' or 'rpm')" >&2; exit 1 ;;
esac

# ---- Derive defaults ----
MAJOR="${WINE_VERSION%%.*}"
[[ -z "$PREFIX"     ]] && PREFIX="/opt/wine-${MAJOR}"
[[ -z "$BUILD_DIR"  ]] && BUILD_DIR="/var/tmp/wine-build-${WINE_VERSION}"
[[ -z "$OUTPUT_DIR" ]] && OUTPUT_DIR="$(pwd)/dist"

WINE_SOURCE_URL="https://dl.winehq.org/wine/source/${WINE_FOLDER}/wine-${WINE_VERSION}.tar.xz"
JOBS="$(nproc)"

# ---- sudo detection (skip when running as root, e.g. in CI containers) ----
if [[ "${EUID}" -eq 0 ]]; then SUDO=""; else SUDO="sudo"; fi

echo "=== Building Wine ${WINE_VERSION} (folder=${WINE_FOLDER}, mode=${MODE}) ==="
echo "    Source URL: ${WINE_SOURCE_URL}"

# ---- [1/5] Enable repositories ----
echo "=== [1/5] Enabling CRB, EPEL, and devel repositories ==="
${SUDO} dnf install -y dnf-plugins-core
${SUDO} dnf config-manager --set-enabled crb
${SUDO} dnf install -y epel-release || true
${SUDO} dnf install -y almalinux-release-devel || true
${SUDO} dnf config-manager --set-enabled devel || true
${SUDO} dnf makecache

# ---- [2/5] Install build dependencies ----
echo "=== [2/5] Installing build dependencies ==="
${SUDO} dnf install -y \
    gcc gcc-c++ make flex bison autoconf automake libtool \
    gettext gettext-devel perl python3 \
    libX11-devel libXext-devel libXrender-devel libXrandr-devel \
    libXcomposite-devel libXcursor-devel libXi-devel libXinerama-devel \
    libXxf86vm-devel libXfixes-devel \
    freetype-devel fontconfig-devel \
    zlib-devel libpng-devel libjpeg-turbo-devel libtiff-devel \
    alsa-lib-devel pulseaudio-libs-devel \
    libgphoto2-devel libv4l-devel \
    gstreamer1-devel gstreamer1-plugins-base-devel \
    libunwind-devel vulkan-loader-devel \
    wayland-devel libxkbcommon-devel \
    mesa-libGL-devel mesa-compat-libOSMesa-devel \
    libva-devel libxml2-devel libxslt-devel \
    gnutls-devel libgcrypt-devel \
    opencl-headers ocl-icd-devel \
    SDL2-devel \
    unixODBC-devel pcsc-lite-devel sane-backends-devel \
    libusb1-devel dbus-devel libcap-devel \
    cups-devel krb5-devel libtirpc-devel \
    libpcap-devel mingw64-gcc mingw32-gcc

if [[ "$MODE" == "rpm" ]]; then
    ${SUDO} dnf install -y rpm-build rpmdevtools
fi

# ---- [3/5] Download source ----
echo "=== [3/5] Downloading Wine ${WINE_VERSION} ==="
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"
if [[ ! -f "wine-${WINE_VERSION}.tar.xz" ]]; then
    curl -fL "${WINE_SOURCE_URL}" -o "wine-${WINE_VERSION}.tar.xz"
fi

# ---- [4/5] + [5/5] ----
if [[ "$MODE" == "install" ]]; then
    echo "=== [4/5] Extracting and compiling ==="
    tar -xf "wine-${WINE_VERSION}.tar.xz"
    cd "wine-${WINE_VERSION}"
    ./configure \
        --prefix="${PREFIX}" \
        --enable-archs=i386,x86_64 \
        --with-x \
        --with-wayland \
        --with-vulkan
    make -j"${JOBS}"

    echo "=== [5/5] Installing to ${PREFIX} ==="
    ${SUDO} make install

    echo ""
    echo "=== Wine ${WINE_VERSION} installed to ${PREFIX} ==="
    echo "Add to ~/.bashrc:"
    echo "  export PATH=\"${PREFIX}/bin:\$PATH\""
    echo "Then: source ~/.bashrc && wine --version"

else
    echo "=== [4/5] Setting up RPM build tree ==="
    rpmdev-setuptree
    cp "wine-${WINE_VERSION}.tar.xz" ~/rpmbuild/SOURCES/

    echo "=== [5/5] Writing spec and building RPM ==="
    cat > ~/rpmbuild/SPECS/wine.spec <<SPEC
Name:           wine
Version:        ${WINE_VERSION}
Release:        2%{?dist}
Summary:        A compatibility layer for running Windows programs
License:        LGPL-2.1-or-later
URL:            https://www.winehq.org/
Source0:        wine-%{version}.tar.xz

BuildRequires:  gcc gcc-c++ make flex bison
BuildRequires:  libX11-devel libXext-devel libXrender-devel
BuildRequires:  freetype-devel fontconfig-devel
BuildRequires:  zlib-devel libpng-devel libjpeg-turbo-devel
BuildRequires:  alsa-lib-devel pulseaudio-libs-devel
BuildRequires:  gstreamer1-devel gstreamer1-plugins-base-devel
BuildRequires:  vulkan-loader-devel wayland-devel libxkbcommon-devel
BuildRequires:  mesa-libGL-devel mesa-compat-libOSMesa-devel
BuildRequires:  libxml2-devel libxslt-devel gnutls-devel
BuildRequires:  SDL2-devel unixODBC-devel

%description
Wine is an Open Source implementation of the Windows API on top of X,
OpenGL, and Unix. It allows you to run Windows applications on Linux
without a Windows license or a virtual machine.

%package devel
Summary:        Development files for Wine
Requires:       %{name} = %{version}-%{release}

%description devel
Headers, import libraries, and static libraries for building Windows
applications against Wine.

# Both of these are required to build loader/wine-preloader under RPM:
#  - hardening specs break the -nostartfiles/-nodefaultlibs link
#  - LTO drops the thread_data / wld_start symbols referenced from inline asm
%undefine _hardened_build
%global _lto_cflags %{nil}

%prep
%autosetup -n wine-%{version}

%build
./configure --prefix=%{_prefix} --libdir=%{_libdir} --enable-archs=i386,x86_64 --with-x --with-wayland --with-vulkan
make %{?_smp_mflags}

%install
make install DESTDIR=%{buildroot}

%files
%{_bindir}/*
%{_libdir}/wine/
%{_datadir}/wine/
%{_datadir}/applications/wine*.desktop
%{_mandir}/man1/*.1*
%{_mandir}/*/man1/*.1*
%exclude %{_includedir}/wine/
%exclude %{_libdir}/wine/*/*.a

%files devel
%{_includedir}/wine/
%{_libdir}/wine/*/*.a

%changelog
* $(date '+%a %b %d %Y') CI <ci@example.com> - ${WINE_VERSION}-1
- Automated build of Wine ${WINE_VERSION}
SPEC

    rpmbuild -bb ~/rpmbuild/SPECS/wine.spec

    mkdir -p "${OUTPUT_DIR}"
    cp ~/rpmbuild/RPMS/x86_64/*.rpm "${OUTPUT_DIR}/"
    echo ""
    echo "=== RPM(s) built: ==="
    ls -la "${OUTPUT_DIR}/"
fi