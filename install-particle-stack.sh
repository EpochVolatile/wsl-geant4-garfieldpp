#!/usr/bin/env bash
set -euo pipefail

# AlmaLinux 9 x86_64 / WSL 2：ROOT 官方二进制 + Geant4 + Garfield++。
# 保存为 UTF-8、LF 文件后执行：bash install-particle-stack.sh
# D 盘布局：将发行版虚拟磁盘放在 D:\WSL，Linux 内仍使用 /opt。
# 不要将编译目录或 /opt 链接到 /mnt/d 的 NTFS 目录。
# 官方资料：
# https://root.cern/download/
# https://root.cern/about/versioning/
# https://geant4.web.cern.ch/download/
# https://gitlab.cern.ch/garfield/garfieldpp
# https://code.visualstudio.com/docs/remote/wsl#_advanced-environment-setup-script
# Garfield++ 按要求取官方默认分支；主分支不具有正式稳定发行版保证。
# VS Code 必须连接此 WSL 发行版；Copilot 仍需有效账号和授权。
# 普通 C++ 项目仍需声明 target_link_libraries；环境变量不能代替链接参数。
# 不升级或锁定发行版：dnf 使用现有官方仓库，可能更新依赖到后续 9.x。

set -E
STAGE=初始化
on_error() {
    local rc=$1 line=$2
    echo "[失败] 阶段：${STAGE}；行：${line}；退出码：${rc}。停止安装，保留构建目录供排查。" >&2
    exit "$rc"
}
trap 'on_error "$?" "$LINENO"' ERR
umask 022
stage() { STAGE=$1; echo; echo "========== $STAGE =========="; }
die() { echo "[错误] $*" >&2; exit 1; }
SUDO=()
if (( EUID != 0 )); then
    command -v sudo >/dev/null || die '请先以 root 安装 sudo，或以 root 运行此脚本。'
    SUDO=(sudo)
    sudo -v
fi

# ---------- 1. 确認目标环境 ----------
stage '1/9 检查 WSL 2、AlmaLinux 和 WSLg'
[[ $(uname -s) == Linux ]] || die '此 Bash 脚本必须在 AlmaLinux WSL 内运行。'
[[ $(uname -m) == x86_64 ]] || die '仅支持 x86_64。'
grep -qi 'microsoft-standard-WSL2' /proc/sys/kernel/osrelease || die '需要 WSL 2 内核。'
# shellcheck disable=SC1091
. /etc/os-release
[[ ${ID:-} == almalinux && ${VERSION_ID:-} == 9.* ]] || die '需要 AlmaLinux 9.x。'
TARGET_MINOR=${VERSION_ID#9.}
[[ $TARGET_MINOR =~ ^[0-9]+$ ]] || die '无法解析 AlmaLinux 版本。'
INITIAL_OS=$PRETTY_NAME
[[ -S /mnt/wslg/.X11-unix/X0 ]] || die '未找到 WSLg X11 插座；请先在 Windows 更新并启动带 WSLg 的 WSL。'
export DISPLAY=${DISPLAY:-:0}
export QT_QPA_PLATFORM=xcb
if [[ -z ${XDG_RUNTIME_DIR:-} && -d /mnt/wslg/runtime-dir ]]; then
    export XDG_RUNTIME_DIR=/mnt/wslg/runtime-dir
fi
echo "系统：$INITIAL_OS；DISPLAY=$DISPLAY"
df -h /opt
echo '编译将使用全部可见 CPU；内存不足会立即失败，不会悄悄降低并行度。'

# ---------- 2. 系统依赖 ----------
stage '2/9 刷新 dnf 缓存并安装依赖'
"${SUDO[@]}" dnf -y makecache --refresh
"${SUDO[@]}" dnf -y install dnf-plugins-core
"${SUDO[@]}" dnf config-manager --set-enabled crb
"${SUDO[@]}" dnf -y install epel-release
"${SUDO[@]}" dnf -y makecache --refresh
"${SUDO[@]}" dnf -y group install 'Development Tools'
"${SUDO[@]}" dnf -y install \
    gcc gcc-c++ gcc-gfortran make cmake git wget curl ca-certificates \
    tar gzip bzip2 xz unzip which file diffutils patch findutils procps-ng \
    python3 python3-devel python3-numpy xerces-c-devel expat-devel zlib-devel gsl-devel \
    libX11-devel libXext-devel libXft-devel libXpm-devel libXi-devel \
    libXmu-devel libXrandr-devel libXrender-devel libXinerama-devel \
    libXcursor-devel libSM-devel libICE-devel libxkbcommon-x11-devel \
    mesa-libGL-devel mesa-libGLU-devel mesa-libEGL mesa-dri-drivers \
    qt5-qtbase-devel qt5-qtsvg-devel qt5-qttools-devel qt5-qtx11extras-devel \
    xcb-util-image xcb-util-keysyms xcb-util-renderutil xcb-util-wm \
    freetype-devel fontconfig-devel dejavu-sans-fonts libpng-devel \
    libjpeg-turbo-devel libtiff-devel giflib-devel fftw-devel \
    openssl-devel pcre-devel pcre2-devel xz-devel bzip2-devel lz4-devel \
    libzstd-devel xxhash-devel tbb-devel libxml2-devel libcurl-devel \
    libglvnd-glx glew-devel ftgl-devel gl2ps-devel \
    gmp-devel gdb

# 使用发行版默认工具链，避免从 Windows/Conda 继承另一套编译器。
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
export CC=/usr/bin/gcc CXX=/usr/bin/g++ FC=/usr/bin/gfortran
unset ROOTSYS GARFIELD_HOME GARFIELD_INSTALL HEED_DATABASE
unset CMAKE_PREFIX_PATH CPATH CPLUS_INCLUDE_PATH C_INCLUDE_PATH LIBRARY_PATH PYTHONPATH
export LD_LIBRARY_PATH=/usr/lib/wsl/lib
GCC_VERSION=$(/usr/bin/gcc -dumpfullversion)
[[ ${GCC_VERSION%%.*} == 11 ]] || die "系统默认 GCC 应为 11，实际为 $GCC_VERSION。"
NCPU=$(nproc)
echo "GCC=$GCC_VERSION；并行度=$NCPU"
cmake --version
python3 --version

# 每次运行使用新的构建/安装目录，不删除既有安装。
"${SUDO[@]}" install -d -m 0755 /opt/particle-stack
WORK=$("${SUDO[@]}" mktemp -d /opt/particle-stack/build.XXXXXXXX)
"${SUDO[@]}" chown "$(id -u):$(id -g)" "$WORK"
RUN_ID=${WORK##*.}
INSTALL_BASE=/opt/particle-stack/releases/$RUN_ID
"${SUDO[@]}" install -d -m 0755 "$INSTALL_BASE"
echo "构建目录：$WORK"
echo "安装目录：$INSTALL_BASE"

# AlmaLinux WSL 镜像可能缺少 Windows 程序的 binfmt 注册，导致 code 无法启动。
# 已在真实部署中复现；仅在缺失时使用 systemd 在开机时恢复官方 /init 处理器。
if [[ ! -e /proc/sys/fs/binfmt_misc/WSLInterop && $(cat /proc/1/comm) == systemd ]]; then
    cat > "$WORK/wsl-interop-restore" <<'WSL_INTEROP'
#!/bin/sh
set -eu
binfmt=/proc/sys/fs/binfmt_misc
if [ ! -e "$binfmt/register" ]; then
    /usr/bin/mount -t binfmt_misc binfmt_misc "$binfmt"
fi
if [ ! -e "$binfmt/WSLInterop" ]; then
    printf '%s\n' ':WSLInterop:M::MZ::/init:P' > "$binfmt/register"
fi
WSL_INTEROP
    cat > "$WORK/wsl-interop.service" <<'WSL_SERVICE'
[Unit]
Description=Restore the WSL Windows executable interpreter when missing
After=systemd-binfmt.service
ConditionPathExists=/init
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/wsl-interop-restore
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
WSL_SERVICE
    "${SUDO[@]}" install -m 0755 "$WORK/wsl-interop-restore" /usr/local/sbin/wsl-interop-restore
    "${SUDO[@]}" install -m 0644 "$WORK/wsl-interop.service" /etc/systemd/system/wsl-interop.service
    "${SUDO[@]}" systemctl daemon-reload
    "${SUDO[@]}" systemctl enable --now wsl-interop.service
fi

download() {
    local url=$1 destination=$2
    echo "下载：$url"
    curl --fail --location --show-error --retry 3 --connect-timeout 30 \
        --proto '=https' --proto-redir '=https' "$url" -o "$destination"
}

# ---------- 3. 运行时选择正式发行版 ----------
stage '3/9 查询官方发行信息'
python3 - "$TARGET_MINOR" "$GCC_VERSION" > "$WORK/releases.txt" <<'PY_RELEASE'
import json
import re
import sys
from html.parser import HTMLParser
from urllib.parse import urljoin, urlsplit
from urllib.request import Request, urlopen

BASE = 'https://root.cern/download/'

class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.hrefs = []
    def handle_starttag(self, tag, attrs):
        if tag == 'a':
            href = dict(attrs).get('href')
            if href:
                self.hrefs.append(href)

def select_root(html, os_minor, gcc):
    parser = Links()
    parser.feed(html)
    pattern = re.compile(
        r'root_v(\d+)\.(\d+)\.(\d+)\.Linux-'
        r'(almalinux|centos)9(?:\.(\d+))?-x86_64-gcc'
        r'(\d+)(?:\.(\d+))?(?:\.(\d+))?\.tar\.gz')
    candidates = []
    for href in parser.hrefs:
        url = urlsplit(urljoin(BASE, href))
        if url.scheme != 'https' or url.netloc != 'root.cern' or url.query or url.fragment:
            continue
        if not url.path.startswith('/download/'):
            continue
        name = url.path[len('/download/'):]
        match = pattern.fullmatch(name)
        if not match:
            continue
        version = tuple(map(int, match.group(1, 2, 3)))
        distro = match.group(4)
        minor = int(match.group(5) or 0)
        compiler = tuple(int(x or 0) for x in match.group(6, 7, 8))
        # ROOT 正式版 minor、patch 均为偶数；不接受 rc/nightly。
        if version[1] % 2 or version[2] % 2:
            continue
        if minor > os_minor or compiler[0] != gcc[0] or compiler > gcc:
            continue
        # AlmaLinux 必须注明小版本，不能对未知构建环境作兼容承诺。
        if distro == 'almalinux' and match.group(5) is None:
            continue
        candidates.append((version, distro == 'almalinux', minor, compiler, name))
    if not candidates:
        raise RuntimeError('官方目录中没有符合本机 AlmaLinux/GCC 约束的稳定 ROOT 二进制；不回退源码编译。')
    version, _, _, _, name = max(candidates)
    return '%d.%02d.%02d' % version, name

def fetch(url):
    request = Request(url, headers={'User-Agent': 'AlmaLinux-particle-stack-installer'})
    with urlopen(request, timeout=90) as response:
        return response.read().decode('utf-8')

if __name__ == '__main__':
    minor = int(sys.argv[1])
    gcc = tuple(map(int, sys.argv[2].split('.')))
    gcc = (gcc + (0, 0, 0))[:3]
    release = json.loads(fetch('https://api.github.com/repos/Geant4/geant4/releases/latest'))
    tag = release['tag_name']
    if release.get('draft') or release.get('prerelease') or not re.fullmatch(r'v\d+\.\d+\.\d+', tag):
        raise RuntimeError('Geant4 latest 元数据不是正式版，停止而不猜测版本。')
    version, filename = select_root(fetch(BASE), minor, gcc)
    print(tag[1:])
    print('https://gitlab.cern.ch/geant4/geant4/-/archive/' + tag + '/geant4-' + tag + '.tar.gz')
    print(version)
    print(BASE + filename)
PY_RELEASE
mapfile -t RELEASES < "$WORK/releases.txt"
[[ ${#RELEASES[@]} == 4 ]] || die '官方发行信息不完整。'
G4_VERSION=${RELEASES[0]}
G4_URL=${RELEASES[1]}
ROOT_VERSION=${RELEASES[2]}
ROOT_URL=${RELEASES[3]}
ROOT_PREFIX=$INSTALL_BASE/root-$ROOT_VERSION
G4_PREFIX=$INSTALL_BASE/geant4-$G4_VERSION
GARFIELD_PREFIX=$INSTALL_BASE/garfieldpp
echo "Geant4 最新正式版：$G4_VERSION"
echo "ROOT 最新兼容正式二进制：$ROOT_VERSION（构建系统不高于初始 AlmaLinux 9.$TARGET_MINOR）"
echo "ROOT 包：$ROOT_URL"

# ---------- 4. ROOT：仅使用官方预编译包 ----------
stage '4/9 安装并验证 ROOT'
download "$ROOT_URL" "$WORK/root.tar.gz"
"${SUDO[@]}" install -d -m 0755 "$ROOT_PREFIX"
"${SUDO[@]}" tar -xzf "$WORK/root.tar.gz" -C "$ROOT_PREFIX" \
    --strip-components=1 --no-same-owner --no-same-permissions
# 官方环境脚本不承诺兼容 nounset；仅在加载它们时暂时关闭 -u。
set +u
# shellcheck disable=SC1091
. "$ROOT_PREFIX/bin/thisroot.sh"
set -u
root-config --version
CXXSTD=$(root-config --cxxstandard)
[[ $CXXSTD =~ ^(17|20|23)$ ]] || die "ROOT C++ 标准不受此脚本支持：$CXXSTD"
[[ $(root-config --has-gdml) == yes ]] || die 'ROOT 二进制缺少 Garfield++ 必需的 GDML 支持。'
ROOT_PYTHON=$(root-config --python3-version)
SYSTEM_PYTHON=$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])')
[[ $ROOT_PYTHON == "$SYSTEM_PYTHON" || $ROOT_PYTHON == "$SYSTEM_PYTHON".* ]] || \
    die "ROOT 要求 Python $ROOT_PYTHON，系统为 $SYSTEM_PYTHON。"
root -l -b -q -e 'TH1D h("check","check",10,0,10); h.Fill(1); if(h.GetEntries()!=1) gSystem->Exit(1); std::cout << gROOT->GetVersion() << std::endl; gSystem->Exit(0);'
python3 - <<'PY_ROOT'
import ROOT
ROOT.gROOT.SetBatch(True)
h = ROOT.TH1D('python_check', '', 10, 0, 10)
h.Fill(1)
assert h.GetEntries() == 1
print('PyROOT:', ROOT.gROOT.GetVersion())
PY_ROOT
echo '[通过] ROOT 命令、解释器、直方图与 PyROOT。'

# ---------- 5. Geant4：GDML、Qt5、多线程、物理数据 ----------
stage '5/9 编译并验证 Geant4'
download "$G4_URL" "$WORK/geant4.tar.gz"
mkdir -p "$WORK/geant4-src"
tar -xzf "$WORK/geant4.tar.gz" -C "$WORK/geant4-src" --strip-components=1
cmake -S "$WORK/geant4-src" -B "$WORK/geant4-build" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$G4_PREFIX" \
    -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_CXX_STANDARD="$CXXSTD" \
    -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
    -DGEANT4_USE_GDML=ON -DGEANT4_USE_QT=ON -DGEANT4_USE_QT_QT5=ON \
    -DGEANT4_USE_OPENGL_X11=ON -DGEANT4_BUILD_MULTITHREADED=ON \
    -DGEANT4_INSTALL_DATA=ON -DGEANT4_INSTALL_DATA_TIMEOUT=7200 \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
cmake --build "$WORK/geant4-build" -- -j"$(nproc)"
"${SUDO[@]}" cmake --install "$WORK/geant4-build"
set +u
# shellcheck disable=SC1091
. "$G4_PREFIX/bin/geant4.sh"
set -u
geant4-config --version
for feature in gdml qt multithreading; do
    [[ $(geant4-config --has-feature "$feature") == yes ]] || die "Geant4 未启用 $feature。"
done
geant4-config --check-datasets | tee "$WORK/geant4-datasets-check.txt"
if grep -q NOTFOUND "$WORK/geant4-datasets-check.txt"; then
    die 'Geant4 物理数据不完整。'
fi
geant4-config --datasets > "$WORK/geant4-datasets.txt"
[[ -s $WORK/geant4-datasets.txt ]] || die 'Geant4 没有报告物理数据。'

# 一个真正执行五个粒子事件的程序，同时作为自动关闭的 Qt5 GUI 测试。
mkdir -p "$WORK/g4-check"
cat > "$WORK/g4-check/CMakeLists.txt" <<'CMAKE_G4'
cmake_minimum_required(VERSION 3.16)
project(g4_check LANGUAGES CXX)
find_package(Geant4 REQUIRED ui_all vis_all)
find_package(Qt5 REQUIRED COMPONENTS Core Widgets)
include(${Geant4_USE_FILE})
add_executable(g4-check main.cc)
target_link_libraries(g4-check PRIVATE ${Geant4_LIBRARIES} Qt5::Core Qt5::Widgets)
CMAKE_G4
cat > "$WORK/g4-check/main.cc" <<'CPP_G4'
#include <memory>
#include <string>
#include <G4Box.hh>
#include <G4LogicalVolume.hh>
#include <G4NistManager.hh>
#include <G4PVPlacement.hh>
#include <G4VUserDetectorConstruction.hh>
#include <G4VUserPrimaryGeneratorAction.hh>
#include <G4VUserActionInitialization.hh>
#include <G4ParticleGun.hh>
#include <G4Electron.hh>
#include <G4RunManagerFactory.hh>
#include <G4Run.hh>
#include <G4UImanager.hh>
#include <G4UIExecutive.hh>
#include <G4VisExecutive.hh>
#include <G4SystemOfUnits.hh>
#include <FTFP_BERT.hh>
#include <QCoreApplication>
#include <QTimer>
class Detector : public G4VUserDetectorConstruction {
 public:
  G4VPhysicalVolume* Construct() override {
    auto material = G4NistManager::Instance()->FindOrBuildMaterial("G4_Si");
    auto solid = new G4Box("world", .5*m, .5*m, .5*m);
    auto logical = new G4LogicalVolume(solid, material, "world");
    return new G4PVPlacement(nullptr, {}, logical, "world", nullptr, false, 0);
  }
};
class Primary : public G4VUserPrimaryGeneratorAction {
  G4ParticleGun gun{1};
 public:
  Primary() {
    gun.SetParticleDefinition(G4Electron::Definition());
    gun.SetParticleEnergy(10*MeV);
    gun.SetParticlePosition({0, 0, -49*cm});
    gun.SetParticleMomentumDirection({0, 0, 1});
  }
  void GeneratePrimaries(G4Event* event) override { gun.GeneratePrimaryVertex(event); }
};
class Actions : public G4VUserActionInitialization {
 public:
  void Build() const override { SetUserAction(new Primary); }
};
int main(int argc, char** argv) {
  const bool gui = argc > 1 && std::string(argv[1]) == "--gui";
  std::unique_ptr<G4UIExecutive> ui;
  if (gui) ui = std::make_unique<G4UIExecutive>(argc, argv, "Qt");
  std::unique_ptr<G4RunManager> run(G4RunManagerFactory::CreateRunManager(G4RunManagerType::MT));
  run->SetUserInitialization(new Detector);
  run->SetUserInitialization(new FTFP_BERT);
  run->SetUserInitialization(new Actions);
  auto commands = G4UImanager::GetUIpointer();
  if (commands->ApplyCommand("/run/numberOfThreads 2") != 0) return 2;
  if (commands->ApplyCommand("/run/initialize") != 0) return 3;
  if (commands->ApplyCommand("/run/beamOn 5") != 0) return 4;
  if (!run->GetCurrentRun() || run->GetCurrentRun()->GetNumberOfEvent() != 5) return 5;
  if (gui) {
    if (!ui->IsGUI()) return 6;
    G4VisExecutive vis;
    vis.Initialize();
    if (commands->ApplyCommand("/vis/open OGLSQt") != 0) return 7;
    if (commands->ApplyCommand("/vis/drawVolume") != 0) return 8;
    if (commands->ApplyCommand("/vis/viewer/update") != 0) return 9;
    QTimer::singleShot(2500, QCoreApplication::instance(), &QCoreApplication::quit);
    ui->SessionStart();
  }
  G4cout << "Geant4: five events passed" << G4endl;
}
CPP_G4
cmake -S "$WORK/g4-check" -B "$WORK/g4-check/build" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_STANDARD="$CXXSTD" \
    -DCMAKE_PREFIX_PATH="$G4_PREFIX;$ROOT_PREFIX"
cmake --build "$WORK/g4-check/build" -- -j"$(nproc)"
"$WORK/g4-check/build/g4-check"
echo '[通过] Geant4 多线程物理模拟与数据加载。'

# ---------- 6. Garfield++：官方默认分支，链接上述 ROOT ----------
stage '6/9 编译并验证 Garfield++'
git clone --depth 1 --recurse-submodules \
    https://gitlab.cern.ch/garfield/garfieldpp.git "$WORK/garfield-src"
GARFIELD_BRANCH=$(git -C "$WORK/garfield-src" branch --show-current)
GARFIELD_COMMIT=$(git -C "$WORK/garfield-src" rev-parse HEAD)
echo "Garfield++ 默认分支：$GARFIELD_BRANCH；Git 提交：$GARFIELD_COMMIT"
cmake -S "$WORK/garfield-src" -B "$WORK/garfield-build" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$GARFIELD_PREFIX" \
    -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_CXX_STANDARD="$CXXSTD" \
    -DCMAKE_CXX_COMPILER="$CXX" -DCMAKE_Fortran_COMPILER="$FC" \
    -DPython_EXECUTABLE=/usr/bin/python3 \
    -DCMAKE_PREFIX_PATH="$ROOT_PREFIX" -DROOT_DIR="$ROOT_PREFIX/cmake" \
    -DGARFIELD_WITH_CUDA=OFF -DGARFIELD_WITH_EXAMPLES=OFF \
    -DGARFIELD_WITH_TESTS=OFF -DGARFIELD_WITH_DOC=OFF \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
cmake --build "$WORK/garfield-build" -- -j"$(nproc)"
"${SUDO[@]}" cmake --install "$WORK/garfield-build"
set +u
# shellcheck disable=SC1091
. "$GARFIELD_PREFIX/share/Garfield/setupGarfield.sh"
set -u
mkdir -p "$WORK/stack-check"
cat > "$WORK/stack-check/CMakeLists.txt" <<'CMAKE_STACK'
cmake_minimum_required(VERSION 3.16)
project(stack_check LANGUAGES CXX)
find_package(ROOT REQUIRED COMPONENTS Core Hist Geom Gdml MathCore)
find_package(Garfield REQUIRED)
add_executable(stack-check main.cc)
target_link_libraries(stack-check PRIVATE Garfield::Garfield ROOT::Core ROOT::Hist)
CMAKE_STACK
cat > "$WORK/stack-check/main.cc" <<'CPP_STACK'
#include <cmath>
#include <iostream>
#include <TH1D.h>
#include <TROOT.h>
#include <Garfield/MediumMagboltz.hh>
#include <Garfield/TrackHeed.hh>
int main() {
  gROOT->SetBatch(true);
  TH1D histogram("check", "check", 10, 0., 10.);
  histogram.Fill(2.);
  if (histogram.GetEntries() != 1.) return 1;
  Garfield::MediumMagboltz gas;
  if (!gas.SetComposition("ar", 70., "co2", 30.)) return 2;
  gas.SetTemperature(293.15);
  gas.SetPressure(760.);
  if (!gas.Initialise(false)) return 3;
  const auto rate = gas.GetElectronCollisionRate(10., 0);
  if (!std::isfinite(rate) || rate <= 0.) return 4;
  Garfield::TrackHeed heed;
  heed.SetParticle("mu-");
  heed.SetMomentum(1.e9);
  if (!heed.Initialise(&gas, false)) return 5;
  std::cout << "ROOT + Garfield++ + Magboltz + Heed passed\n";
}
CPP_STACK
cmake -S "$WORK/stack-check" -B "$WORK/stack-check/build" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_STANDARD="$CXXSTD" \
    -DCMAKE_PREFIX_PATH="$ROOT_PREFIX;$GARFIELD_PREFIX"
cmake --build "$WORK/stack-check/build" -- -j"$(nproc)"
"$WORK/stack-check/build/stack-check"
echo '[通过] Garfield++ 编译、链接、Magboltz 计算与 Heed 数据加载。'

# ---------- 7. 真正创建 WSLg 窗口；不能用 batch/offscreen 冒充 GUI 成功 ----------
stage '7/9 验证 ROOT 与 Geant4 的 WSLg GUI'
timeout 45s root -l -q -e 'if(gROOT->IsBatch()) gSystem->Exit(1); TCanvas c("wslg_check","ROOT WSLg check",640,400); TH1D h("gui_h","ROOT WSLg",20,0,20); h.Fill(10); h.Draw(); c.Update(); gSystem->ProcessEvents(); if(c.GetWindowWidth()==0) gSystem->Exit(2); gSystem->Sleep(2500); gSystem->Exit(0);'
timeout 90s "$WORK/g4-check/build/g4-check" --gui
echo '[通过] ROOT X11 窗口与 Geant4 Qt5/OpenGL 窗口。'

# ---------- 8. 全局环境及 VS Code WSL 启动环境 ----------
stage '8/9 安装全局环境和 VS Code WSL 入口'
link_prefix() {
    local target=$1 link=$2
    if [[ -e $link && ! -L $link ]]; then
        die "$link 是既有实体目录/文件；为保护原安装，不覆盖。新安装已保存在 $target。"
    fi
    "${SUDO[@]}" ln -sfnT "$target" "$link"
}
link_prefix "$ROOT_PREFIX" /opt/root
link_prefix "$G4_PREFIX" /opt/geant4
link_prefix "$GARFIELD_PREFIX" /opt/garfieldpp

# 独立 POSIX 环境脚本：兼容 Bash 登录会话与 VS Code 的 /bin/sh。
cat > "$WORK/90-particle-root.sh" <<'ENV_ROOT'
export ROOTSYS=/opt/root
export PATH="/opt/root/bin${PATH:+:$PATH}"
export LD_LIBRARY_PATH="/opt/root/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PYTHONPATH="/opt/root/lib${PYTHONPATH:+:$PYTHONPATH}"
export CMAKE_PREFIX_PATH="/opt/root${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
export CPATH="/opt/root/include${CPATH:+:$CPATH}"
export LIBRARY_PATH="/opt/root/lib${LIBRARY_PATH:+:$LIBRARY_PATH}"
ENV_ROOT
cat > "$WORK/91-particle-geant4.sh" <<'ENV_G4'
export PATH="/opt/geant4/bin${PATH:+:$PATH}"
export LD_LIBRARY_PATH="/opt/geant4/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export CMAKE_PREFIX_PATH="/opt/geant4${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
export CPATH="/opt/geant4/include/Geant4${CPATH:+:$CPATH}"
export LIBRARY_PATH="/opt/geant4/lib${LIBRARY_PATH:+:$LIBRARY_PATH}"
ENV_G4
while read -r data_name data_variable data_path; do
    [[ $data_variable =~ ^[A-Z][A-Z0-9_]*$ && -d $data_path ]] || die "物理数据条目无效：$data_name"
    [[ $data_path != *"'"* ]] || die '物理数据路径含不支持的引号。'
    printf "export %s='%s'\n" "$data_variable" "$data_path" >> "$WORK/91-particle-geant4.sh"
done < "$WORK/geant4-datasets.txt"
cat > "$WORK/92-particle-garfield.sh" <<'ENV_GARFIELD'
export GARFIELD_HOME=/opt/garfieldpp
export GARFIELD_INSTALL=/opt/garfieldpp
export HEED_DATABASE=/opt/garfieldpp/share/Heed/database
export LD_LIBRARY_PATH="/opt/garfieldpp/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export CMAKE_PREFIX_PATH="/opt/garfieldpp${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
export CPATH="/opt/garfieldpp/include${CPATH:+:$CPATH}"
export LIBRARY_PATH="/opt/garfieldpp/lib${LIBRARY_PATH:+:$LIBRARY_PATH}"
ENV_GARFIELD
# 留给未来的登录 shell 展开，而不是在安装时展开。
# shellcheck disable=SC2016
printf 'export PYTHONPATH="/opt/garfieldpp/lib/python%s/site-packages${PYTHONPATH:+:$PYTHONPATH}"\n' \
    "$SYSTEM_PYTHON" >> "$WORK/92-particle-garfield.sh"
for profile in "$WORK"/9[012]-particle-*.sh; do
    "${SUDO[@]}" install -m 0644 "$profile" /etc/profile.d/
done
cat > "$WORK/particle-stack.conf" <<'LDCONF'
/opt/root/lib
/opt/geant4/lib
/opt/garfieldpp/lib
LDCONF
"${SUDO[@]}" install -m 0644 "$WORK/particle-stack.conf" /etc/ld.so.conf.d/particle-stack.conf
"${SUDO[@]}" ldconfig
cat > "$WORK/hep-env" <<'ENV_WRAPPER'
#!/bin/sh
set -e
. /etc/profile.d/90-particle-root.sh
. /etc/profile.d/91-particle-geant4.sh
. /etc/profile.d/92-particle-garfield.sh
if [ "$#" -eq 0 ]; then exec /bin/bash -l; fi
exec "$@"
ENV_WRAPPER
"${SUDO[@]}" install -m 0755 "$WORK/hep-env" /usr/local/bin/hep-env

# 不覆盖用户已有设置；为已有本地用户及未来通过 /etc/skel 创建的用户追加入口。
"${SUDO[@]}" /usr/bin/python3 - <<'PY_VSCODE'
import os
import pathlib
import pwd

block = '''
# particle-stack environment
. /etc/profile.d/90-particle-root.sh
. /etc/profile.d/91-particle-geant4.sh
. /etc/profile.d/92-particle-garfield.sh
'''
users = [(pathlib.Path('/etc/skel'), 0, 0)]
for user in pwd.getpwall():
    if (user.pw_uid == 0 or 1000 <= user.pw_uid < 65534) and user.pw_shell not in ('/sbin/nologin', '/bin/false'):
        directory = pathlib.Path(user.pw_dir)
        if directory.is_dir():
            users.append((directory, user.pw_uid, user.pw_gid))
for home, uid, gid in users:
    for name in ('.vscode-server', '.vscode-server-insiders'):
        directory = home / name
        directory.mkdir(mode=0o755, parents=True, exist_ok=True)
        os.chown(directory, uid, gid)
        setup = directory / 'server-env-setup'
        old = setup.read_text() if setup.exists() else '#!/bin/sh\n'
        if '# particle-stack environment' not in old:
            lines = old.splitlines(keepends=True)
            first = 1 if lines and lines[0].startswith('#!') else 0
            setup.write_text(''.join(lines[:first]) + block + ''.join(lines[first:]))
            os.chown(setup, uid, gid)
            os.chmod(setup, 0o755)
        print('VS Code WSL:', setup)
PY_VSCODE

# Windows 的 code 启动脚本会把这些扩展装到当前 WSL 用户的 Linux Server。
if command -v code >/dev/null && [[ $(command -v code) == /mnt/*/bin/code ]]; then
    code --install-extension ms-vscode.cpptools --install-extension ms-vscode.cmake-tools
    code --list-extensions > "$WORK/vscode-extensions.txt"
    grep -Fx ms-vscode.cpptools "$WORK/vscode-extensions.txt"
    grep -Fx ms-vscode.cmake-tools "$WORK/vscode-extensions.txt"
else
    echo '未找到 Windows 的 VS Code 启动脚本；Linux 全局环境及远端环境入口已配置。'
fi

# 保存可独立运行的测试和 CMake 示例。
"${SUDO[@]}" install -d -m 0755 /opt/particle-stack/bin /opt/particle-stack/examples
"${SUDO[@]}" install -m 0755 "$WORK/g4-check/build/g4-check" /opt/particle-stack/bin/
"${SUDO[@]}" install -m 0755 "$WORK/stack-check/build/stack-check" /opt/particle-stack/bin/
"${SUDO[@]}" install -d -m 0755 /opt/particle-stack/examples/"stack-check-$RUN_ID"
"${SUDO[@]}" install -m 0644 "$WORK/stack-check/CMakeLists.txt" "$WORK/stack-check/main.cc" \
    /opt/particle-stack/examples/"stack-check-$RUN_ID"/
cat > "$WORK/particle-stack-versions" <<VERSIONS
Initial OS: $INITIAL_OS
GCC: $GCC_VERSION
ROOT: $ROOT_VERSION
ROOT archive: $ROOT_URL
ROOT C++ standard: $CXXSTD
Geant4: $G4_VERSION
Geant4 archive: $G4_URL
Garfield++ branch: $GARFIELD_BRANCH
Garfield++ commit: $GARFIELD_COMMIT
Installation: $INSTALL_BASE
VERSIONS
"${SUDO[@]}" install -m 0644 "$WORK/particle-stack-versions" /opt/particle-stack/versions.txt

# ---------- 9. 从干净进程验证全局环境 ----------
stage '9/9 全局环境与版本自检'
env -i HOME="$HOME" PATH=/usr/local/bin:/usr/bin:/bin \
    /usr/local/bin/hep-env /bin/bash -euc '
        command -v root root-config geant4-config cmake g++
        root-config --version
        geant4-config --version
        python3 -c "import ROOT; print(\"PyROOT:\", ROOT.gROOT.GetVersion())"
        python3 -c "import ROOT, Garfield; gas = ROOT.Garfield.MediumMagboltz(); assert gas.SetComposition(\"ar\",70.,\"co2\",30.); print(\"Garfield Python: passed\")"
        /opt/particle-stack/bin/g4-check
        /opt/particle-stack/bin/stack-check
    '
cat > "$WORK/verify-no-paths.sh" <<'VERIFY_NO_PATHS'
#!/usr/bin/env bash
set -euo pipefail

# Install a source-only example; verify discovery in an unprivileged login shell.
(( EUID == 0 )) || { echo 'Run with sudo bash verify-no-paths.sh' >&2; exit 1; }
example=/opt/particle-stack/examples/all-components
install -d -m 0755 "$example"
cat > "$example/CMakeLists.txt" <<'CMAKE'
cmake_minimum_required(VERSION 3.16)
project(all_components LANGUAGES CXX)
find_package(ROOT REQUIRED COMPONENTS Core Hist)
find_package(Geant4 REQUIRED)
find_package(Garfield REQUIRED)
include(${Geant4_USE_FILE})
add_executable(all-components main.cc)
target_compile_features(all-components PRIVATE cxx_std_17)
target_link_libraries(all-components PRIVATE
  Garfield::Garfield ${Geant4_LIBRARIES} ROOT::Core ROOT::Hist)
CMAKE
cat > "$example/main.cc" <<'CPP'
#include <iostream>
#include <TH1D.h>
#include <TROOT.h>
#include <Garfield/MediumMagboltz.hh>
#include <G4Material.hh>
#include <G4NistManager.hh>
#include <G4Version.hh>

int main() {
  gROOT->SetBatch(true);
  TH1D histogram("all_components", "", 10, 0., 10.);
  histogram.Fill(2.);
  if (histogram.GetEntries() != 1.) return 1;
  Garfield::MediumMagboltz gas;
  if (!gas.SetComposition("ar", 70., "co2", 30.)) return 2;
  const auto material = G4NistManager::Instance()->FindOrBuildMaterial("G4_Si");
  if (!material || !(material->GetDensity() > 0.)) return 3;
  std::cout << "ROOT " << gROOT->GetVersion() << '\n'
            << G4Version << '\n'
            << "Garfield++ Ar/CO2 composition: passed\n"
            << "ROOT histogram + Garfield++ gas + Geant4 material: passed\n";
}
CPP
chmod 0644 "$example/CMakeLists.txt" "$example/main.cc"

test_dir=$(mktemp -d /tmp/particle-stack-no-paths.XXXXXXXX)
trap 'rm -rf -- "$test_dir"' EXIT
install -d -m 0755 "$test_dir/home"
chown -R "$(id -u nobody):$(id -g nobody)" "$test_dir"

runuser -u nobody -- env -i \
  HOME="$test_dir/home" USER=nobody LOGNAME=nobody \
  PATH=/usr/local/bin:/usr/bin:/bin \
  /bin/bash -lc '
    set -euo pipefail
    [[ $(id -u) == "$(id -u nobody)" ]]
    cd "$HOME"
    echo "Unprivileged clean login: $(id -un)"
    command -v root root-config geant4-config cmake g++
    root-config --version
    geant4-config --version
    standard=$(root-config --cxxstandard)
    [[ $standard =~ ^(17|20|23)$ ]]
    source_dir=/opt/particle-stack/examples/all-components

    # No package-location overrides: use only the installed global environment.
    cmake -S "$source_dir" -B cmake-build \
      -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_STANDARD="$standard"
    cmake --build cmake-build -- -j"$(nproc)"
    ./cmake-build/all-components
    echo "CMake package discovery without prefix/directory flags: passed"

    # Explicit library names are required; include/library directories are global.
    g++ -std="c++$standard" "$source_dir/main.cc" -o manual-check \
      -lGarfield -lG4materials -lG4global -lCore -lHist
    ./manual-check
    echo "Manual g++ without -I/-L: passed"
  '
printf 'Source-only example installed: %s\n' "$example"
VERIFY_NO_PATHS
"${SUDO[@]}" bash "$WORK/verify-no-paths.sh"
cat /opt/particle-stack/versions.txt
echo '[通过] ROOT / PyROOT / Geant4 / Garfield++ / Magboltz / Heed / WSLg GUI。'
echo '全局路径：/opt/root、/opt/geant4、/opt/garfieldpp。'
echo '新登录终端自动生效；已运行的终端和 VS Code Server 需重新打开以读取环境。'
echo '无登录 shell 的任务可执行：hep-env <命令>。'
echo 'VS Code 请使用 WSL 扩展连接此发行版；C/C++、CMake Tools、Copilot 扩展及账号登录由 VS Code 管理。'
echo 'CMake 示例：/opt/particle-stack/examples；构建目录已保留，方便查看日志和 compile_commands.json。'
