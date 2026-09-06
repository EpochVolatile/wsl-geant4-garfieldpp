# 在 Windows 上部署 WSL、VS Code、Geant4、ROOT 与 Garfield++

本项目帮助你在 Windows 的 **WSL 2 + AlmaLinux 9 x86_64** 中安装粒子模拟与探测器开发环境，并通过 Windows 版 VS Code 连接 Linux 编写、编译和调试程序。

**已经安装好了？** 请直接阅读[日常仿真操作手册](docs/DAILY_SIMULATION_GUIDE.zh-CN.md)：连接 WSL、写代码、编译测试、断点调试、Geant4 B1 GUI 和 Garfield++ 电场 GUI。

安装完成后，新登录的 Linux 终端可直接使用 `root`、`root-config`、`geant4-config`、`cmake` 和 `g++`。CMake 能发现 ROOT、Geant4、Garfield++；普通 C++ 编译无需手写这些库的 `-I`、`-L` 目录。程序仍须声明使用哪些库，例如 CMake 的 `target_link_libraries` 或编译器的 `-lGarfield`。

**本仓库提供脚本和示例，不附带 WSL 镜像、软件二进制、物理数据库或个人运行日志。** 安装时从各项目的官方来源下载。已有真实机器上的编译、模拟、图形界面和普通用户编译验证；验证范围与尚未完成的验证见[实测记录](#实测记录与验证边界)。

## 阅读路线

第一次安装，按下面的顺序操作：

1. [准备电脑与下载仓库](#1-准备电脑与下载仓库)。
2. [先安装 Windows 版 VS Code 和 WSL 扩展](#2-先安装-windows-版-vs-code-和-wsl-扩展)。
3. [用管理员 PowerShell 启用 WSL，然后重启 Windows](#3-管理员-powershell启用-wsl-并重启)。
4. [用普通 PowerShell 导入 AlmaLinux 并安装软件](#4-普通-powershell导入-almalinux-并安装软件)。
5. [验证结果](#5-进入-linux-检查安装结果)，然后[在 VS Code 中打开第一个项目](#8-在-vs-code-中开发与调试)。

已有合适的 AlmaLinux WSL 环境，可直接阅读[已有发行版的安装方法](#已有-almalinux-9-wsl-发行版)。遇到问题先看[故障排查](#10-故障排查)，不用重新删除发行版。

## 1. 准备电脑与下载仓库

### 1.1 适用环境

本项目面向 Intel/AMD 的 **x86_64 Windows 电脑**，脚本会检查 WSL 2、AlmaLinux 9 和 WSLg。ARM64、WSL 1、Ubuntu、原生 Windows 的 MSVC 构建不在这套脚本的支持范围内。

图形程序要求 Windows 11，或支持 WSLg 的 Windows 10 Build 19044 及以上版本。可按 `Win + R`，输入 `winver` 查看版本。电脑还需启用硬件虚拟化；任务管理器的“性能 → CPU”页面通常能看到“虚拟化”状态。WSLg 的系统要求和显卡驱动说明见 [Microsoft 官方文档](https://learn.microsoft.com/en-us/windows/wsl/tutorials/gui-apps)。

Geant4、Garfield++ 会从源码编译，Geant4 还会下载物理数据。请为安装盘保留充足空间，并接通电源、避免安装期间休眠。脚本使用 `nproc` 报告的全部逻辑 CPU，不承诺固定完成时间，也不会在内存不足时自动降低并行度。

需要能够连接 GitHub、CERN、AlmaLinux/EPEL 软件仓库和 VS Code 下载服务。Windows 能打开网页，不一定意味着 WSL 内的代理配置已经正确；网络问题请按实际失败网址排查。

### 1.2 三种操作位置

本文会明确标注命令的执行位置。不要把不同窗口中的命令整段混着执行。

| 位置 | 怎么打开 | 在这里执行什么 |
| --- | --- | --- |
| **Windows 管理员 PowerShell** | 开始菜单搜索 PowerShell，右键“以管理员身份运行” | 启用/更新 WSL 等系统操作 |
| **Windows 普通 PowerShell** | 正常打开 PowerShell 或 Windows Terminal 的 PowerShell 标签页 | 下载项目、导入发行版、运行 Windows 侧安装入口 |
| **AlmaLinux 终端** | 在 PowerShell 输入 `wsl -d AlmaLinux-9.6 -u root` | `dnf`、`bash`、`root`、`cmake`、`g++` 等 Linux 命令 |

PowerShell 提示符通常像 `PS D:\src>`；Linux 提示符通常包含 `root@...`、`$` 或 `#`。示例代码块不带这些提示符，复制命令本身即可。在 Linux 输入 `exit` 可以回到启动它的 PowerShell。

Windows 脚本支持 Windows PowerShell 5.1 和 PowerShell 7。本文的 `powershell.exe` 命令使用 Windows 自带的 PowerShell；已安装 PowerShell 7 的用户也可以在 `pwsh` 中执行这些脚本。

### 1.3 下载本仓库

不会使用 Git 也可以安装：

1. 打开[本项目 GitHub 页面](https://github.com/EpochVolatile/wsl-geant4-garfieldpp)。
2. 点击绿色 **Code → Download ZIP**。
3. 解压到你有写入权限的文件夹。为便于照抄，本文使用 `D:\src\wsl-geant4-garfieldpp`。
4. 确认该文件夹里直接包含 `README.md`、`enable-wsl.ps1`、`resume-wsl-particle-stack.ps1` 和 `install-particle-stack.sh`。不要误进外面多套的一层目录。

如果 Windows 已安装 Git，也可以在**普通 PowerShell**执行：

```powershell
New-Item -ItemType Directory -Path D:\src -Force
Set-Location D:\src
git clone https://github.com/EpochVolatile/wsl-geant4-garfieldpp.git
Set-Location .\wsl-geant4-garfieldpp
```

没有 D 盘可以把仓库放到其他目录；发行版的安装盘也能通过参数修改，见第 4 节。

### 1.4 为什么“装到 D 盘”，Linux 里却使用 `/opt`？

默认布局如下：

| 路径 | 内容 |
| --- | --- |
| Windows：`D:\src\wsl-geant4-garfieldpp` | 本仓库的脚本与文档 |
| Windows：`D:\WSL\Downloads` | 下载的官方 AlmaLinux 镜像 |
| Windows：`D:\WSL\AlmaLinux-9.6` | WSL 发行版的虚拟磁盘等文件 |
| Linux：`/opt/particle-stack` | 软件安装目录、构建目录、版本记录和示例 |
| Linux：`/opt/root`、`/opt/geant4`、`/opt/garfieldpp` | 指向当前安装的固定入口 |
| Linux：`~/projects` | 建议放置自己的 C++ 项目 |

Linux 的 `/opt` 位于该发行版的虚拟磁盘内；把虚拟磁盘放在 D 盘，就让这些 Linux 文件实际占用 D 盘空间。**不要再把 `/opt` 或编译目录链接到 `/mnt/d`。** `/mnt/d` 是直接访问 Windows 文件系统的挂载路径，本项目在 Linux 文件系统内进行编译。

## 2. 先安装 Windows 版 VS Code 和 WSL 扩展

这一步请在运行 Linux 软件安装器**之前**完成。这样安装器发现 Windows 的 `code` 命令时，可以顺便安装当前 WSL 用户的 C/C++ 和 CMake Tools 扩展。

1. 从 [VS Code 官方下载页](https://code.visualstudio.com/Download)下载并安装 **Windows 版 VS Code**。
2. 安装选项中启用 **Add to PATH / 添加到 PATH**。
3. 安装完成后重新打开 PowerShell，使新 PATH 生效。
4. 打开 VS Code，按 `Ctrl + Shift + X` 进入扩展，搜索 **WSL**，安装 Microsoft 发布的扩展，标识为 `ms-vscode-remote.remote-wsl`。

也可以在**普通 PowerShell**中安装该扩展：

```powershell
code --version
code --install-extension ms-vscode-remote.remote-wsl
```

如果提示找不到 `code`，先关闭并重新打开 PowerShell；仍失败则检查 VS Code 安装选项。此时不要把 Windows 的 VS Code 问题误当作 ROOT 或 Geant4 安装失败。Windows 安装说明见 [VS Code 官方文档](https://code.visualstudio.com/docs/setup/windows)。

编辑器界面运行在 Windows，C++ 编译器、调试器和库运行在 AlmaLinux。连接成功后，VS Code 左下角应显示类似 **WSL: AlmaLinux-9.6** 的标识。[官方 WSL 开发说明](https://code.visualstudio.com/docs/remote/wsl)

## 3. 管理员 PowerShell：启用 WSL 并重启

打开**管理员 PowerShell**，进入仓库目录：

```powershell
Set-Location D:\src\wsl-geant4-garfieldpp
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\enable-wsl.ps1
```

这里的 `-ExecutionPolicy Bypass` 只用于这次启动的 PowerShell 进程，不会把整台电脑的执行策略永久改成 Bypass。运行前可以用 VS Code 阅读脚本。

脚本安装稳定版 WSL，并使用 `--no-distribution` 避免顺带安装默认 Ubuntu。它会记录 `enable-wsl.log` 和 `enable-wsl-status.json`，**不会自动重启 Windows**。完成后保存工作，在 Windows 开始菜单中手动选择“重启”。启用 WSL 后需要重启的说明见 [Microsoft 安装文档](https://learn.microsoft.com/en-us/windows/wsl/install)。

重启后，在**普通 PowerShell**检查：

```powershell
wsl --status
wsl --version
```

若 WSL 已经安装且可用，可以跳过启用步骤。若版本较旧，在管理员 PowerShell 运行 `wsl --update`，并按官方提示重启相关环境；本文需要 WSL 2 和 WSLg。

## 4. 普通 PowerShell：导入 AlmaLinux 并安装软件

### 4.1 推荐入口

使用以后实际操作 VS Code 和 WSL 的 **同一个 Windows 账号**，打开**普通 PowerShell**。WSL 发行版按 Windows 用户注册；不要切换到另一个管理员账号进行导入。

```powershell
Set-Location D:\src\wsl-geant4-garfieldpp
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\run-particle-stack-after-reboot.ps1
```

这个入口增加了部署日志和状态记录，内部调用 `resume-wsl-particle-stack.ps1`。也可以直接运行后者，二者选一个即可：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\resume-wsl-particle-stack.ps1
```

脚本会依次：

1. 确认 WSL 已可启动。
2. 下载官方 AlmaLinux 9.6 x64 WSL 镜像。
3. 以名字 `AlmaLinux-9.6` 导入为 WSL 2，默认放在 `D:\WSL\AlmaLinux-9.6`。
4. 以 Linux `root` 用户实际启动发行版并检查系统信息。
5. 运行 `install-particle-stack.sh`，安装依赖、ROOT、Geant4 和 Garfield++，执行功能验证并配置全局环境。

镜像来自 [AlmaLinux 官方 WSL 镜像项目](https://github.com/AlmaLinux/wsl-images)，选用 `v9.6.20250522.0` 发布的 `AlmaLinux-9.6_x64_20250522.0.wsl`。导入方法对应 [Microsoft 的自定义发行版说明](https://learn.microsoft.com/en-us/windows/wsl/use-custom-distro)。

### 4.2 修改盘符、位置或发行版名字

没有 D 盘，或者想用其他安装位置，在**普通 PowerShell**传入参数。例如：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\run-particle-stack-after-reboot.ps1 -DistroName AlmaLinux-HEP -InstallLocation E:\WSL\AlmaLinux-HEP -DownloadDirectory E:\WSL\Downloads
```

之后本文中所有 `wsl -d AlmaLinux-9.6 ...` 都要相应改成 `wsl -d AlmaLinux-HEP ...`。**发行版名字和 Windows 文件夹名字是两个独立参数。** 改名不会自动移动已经注册的发行版。

| 参数 | 默认值 | 作用 |
| --- | --- | --- |
| `-DistroName` | `AlmaLinux-9.6` | 在 `wsl -l -v` 中显示的注册名字 |
| `-InstallLocation` | `D:\WSL\AlmaLinux-9.6` | 发行版虚拟磁盘保存位置 |
| `-DownloadDirectory` | `D:\WSL\Downloads` | 官方镜像下载缓存位置 |
| `-StackScript` | 当前脚本旁的 `install-particle-stack.sh` | 指定 Linux 安装脚本 |
| `-SkipStackInstall` | 未启用 | 仅准备发行版，跳过物理软件安装 |

两个 Windows 安装入口支持这些参数。路径含空格时请加双引号。脚本不会删除已注册发行版，也不会把同名但位于其他位置的发行版直接覆盖；它会报告冲突，让你检查名字和路径。

只导入系统、稍后再装软件：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\resume-wsl-particle-stack.ps1 -SkipStackInstall
```

去掉 `-SkipStackInstall` 再运行，会复用符合名字和位置条件的发行版并开始软件安装。

### 4.3 安装期间看哪里？

Windows 入口会等待 Linux 安装进程结束；较长的编译输出写入仓库目录的日志。可以另开一个**普通 PowerShell**窗口：

```powershell
Set-Location D:\src\wsl-geant4-garfieldpp
Get-Content .\particle-stack-linux.log -Encoding UTF8 -Tail 50 -Wait
```

按 `Ctrl + C` 只会退出这个额外窗口中的日志跟踪。不要在正在执行安装的原窗口里随意中断。

| 文件 | 用途 |
| --- | --- |
| `particle-stack-linux.log` | Linux 安装、编译和测试的标准输出 |
| `particle-stack-linux.err.log` | Linux 标准错误，编译告警和失败详情可能在这里 |
| `particle-stack-install.log` | 包装入口的 PowerShell transcript |
| `deployment-status.json` | 包装入口记录的 installing / completed / failed 状态 |

ROOT 和 Geant4 的图形测试会短暂打开窗口，然后自动关闭，这是正常验证步骤。安装器有明确的九个阶段；不要仅凭软件文件夹已经出现，就判断安装完成。

### 已有 AlmaLinux 9 WSL 发行版

如果你已有其他名字或位置的 AlmaLinux 9 x86_64 WSL 2，不必重新导入。先在**普通 PowerShell**查看名字：

```powershell
wsl -l -v
```

然后进入目标发行版，把下面的名字换成你的实际名字：

```powershell
wsl -d AlmaLinux-9.6 -u root
```

进入 **AlmaLinux 终端**后运行 Windows 上已经下载好的脚本。以本文仓库位置为例：

```bash
cd /mnt/d/src/wsl-geant4-garfieldpp
bash install-particle-stack.sh
```

这里只从 Windows 文件夹读取脚本；下载解包、源码构建和正式安装仍在 Linux 的 `/opt/particle-stack` 内进行。如果使用普通 Linux 用户运行，安装器会在需要提权时调用 `sudo`。

文件应使用 UTF-8 编码和 LF 换行。若曾手工修改脚本，建议在 VS Code 右下角确认换行符是 `LF`。

## 5. 进入 Linux，检查安装结果

安装器成功结束后，在**普通 PowerShell**进入一个新的登录会话：

```powershell
wsl -d AlmaLinux-9.6 -u root
```

在 **AlmaLinux 终端**执行：

```bash
command -v root root-config geant4-config cmake g++
root-config --version
root-config --cxxstandard
geant4-config --version
cat /opt/particle-stack/versions.txt
```

预期 ROOT 入口指向 `/opt/root/bin`，Geant4 入口指向 `/opt/geant4/bin`。版本以你的实际输出为准；安装器会在运行时查询上游，不会永远安装本文实测的版本。

继续检查 Python 接口：

```bash
python3 - <<'PY'
import ROOT
import Garfield
ROOT.gROOT.SetBatch(True)
h = ROOT.TH1D('check', '', 10, 0, 10)
h.Fill(1)
assert h.GetEntries() == 1
gas = ROOT.Garfield.MediumMagboltz()
assert gas.SetComposition('ar', 70., 'co2', 30.)
print('PyROOT / Garfield Python: passed')
print('ROOT:', ROOT.gROOT.GetVersion())
PY
```

运行安装器保留的功能测试：

```bash
/opt/particle-stack/bin/g4-check
/opt/particle-stack/bin/stack-check
geant4-config --check-datasets
```

`g4-check` 会真正执行五个粒子事件；`stack-check` 会测试 ROOT、Garfield++、Magboltz 计算和 Heed 数据加载。Geant4 数据检查不应报告 `NOTFOUND`。

### 图形界面验证

在 **AlmaLinux 终端**先运行：

```bash
root -l
```

看到 `root [0]` 之后，输入下面的 **ROOT C++ 命令**，不要当作 Bash 命令运行：

```cpp
auto c = new TCanvas("demo", "ROOT on WSLg", 800, 500);
auto h = new TH1D("h", "Gaussian example", 100, -4, 4);
h->FillRandom("gaus", 10000);
h->Draw();
c->Update();
```

应能看到直方图窗口。完成后在 ROOT 提示符输入 `.q` 退出，返回 Bash。

Geant4 Qt/OpenGL 测试在 **Bash** 中运行：

```bash
/opt/particle-stack/bin/g4-check --gui
```

它会运行五个事件、打开 Qt/OpenGL 窗口并自动关闭。Geant4 是开发库，常见用法是运行自己编译的模拟程序；没有必要寻找一个通用的 `geant4` 图形主程序。

## 6. 版本如何选择？

| 组件 | 脚本行为 |
| --- | --- |
| AlmaLinux | 从指定的官方 9.6 WSL 镜像开始；包管理使用现有的 AlmaLinux 9 仓库 |
| 编译器 | 使用发行版默认的 GCC / G++ / GFortran 11 工具链 |
| ROOT | 从官方目录选择满足本机约束的最新正式预编译包；不回退源码编译 |
| Geant4 | 查询官方 GitHub 发布信息的最新正式版，从 CERN 官方仓库下载源码编译 |
| Garfield++ | 克隆 CERN 官方仓库默认分支，记录分支及 Git 提交，再从源码编译 |

ROOT 选择器排除 `rc`、开发版本和不合适的架构；按照 ROOT 的正式版本规则检查 minor、patch 均为偶数，并限制构建系统小版本不高于安装开始时的 AlmaLinux 小版本、编译器版本不高于本机相应 GCC 版本。[ROOT 官方版本规则](https://root.cern/about/versioning/)

**“最新兼容正式二进制”不等于“ROOT 全球最新稳定版”。** 截至 2026-09-06，官方最新稳定版为 6.40.04，其 AlmaLinux 9 包面向 9.8；本项目以初始 9.6 系统约束选择并实际验证的是 6.36.06 的 AlmaLinux 9.6 / GCC 11.5 包。[6.40.04 发布页](https://root.cern/releases/release-64004/)、[6.36.06 发布页](https://root.cern/releases/release-63606/)

选择较新的系统构建包，不能仅凭“都是 EL9”就保证其在旧系统上工作。Red Hat 的兼容性指南要求运行环境与构建环境同样新或更新，才有相应保证。[RHEL 9 兼容性指南](https://access.redhat.com/articles/rhel9-abi-compatibility)

AlmaLinux 的 `dnf` 依赖安装可能把部分软件包更新到后续 9.x；本项目没有冻结系统小版本，也没有切换到归档仓库。ROOT 的初始系统约束不会因此被静默放宽。

**Garfield++ 默认分支不能称为“最新稳定发行版”。** 它是本项目选择的上游开发来源，未来运行脚本时可能取得不同提交。请用 `/opt/particle-stack/versions.txt` 查看本次实际使用的版本和提交。

ROOT、Geant4、Garfield++ 使用与 ROOT 二进制匹配的 C++ 标准。自己的项目也应与 `root-config --cxxstandard` 一致；ROOT 官方要求使用它的程序采用相同 C++ 标准。[ROOT 构建说明](https://root.cern/install/build_from_source/)

## 7. 日常使用与普通 Linux 用户

### 7.1 初始用户是 root

Windows 入口显式使用 Linux `root` 执行安装。导入发行版不会像某些商店发行版的首次启动向导那样，自动替你创建日常 Linux 用户。

这里的 Linux root 和 Windows 管理员是不同身份。你可以继续用 `wsl -d AlmaLinux-9.6 -u root` 管理系统；日常编程也可以创建普通 Linux 用户。

### 7.2 可选：创建日常用户

以下在 **AlmaLinux 的 root 终端**执行。`researcher` 是示例用户名，可以换成自己的名字：

```bash
dnf -y install sudo
useradd -m -s /bin/bash -G wheel researcher
passwd researcher
```

`passwd` 会要求输入两次 Linux 密码；输入时不显示字符是正常现象。本教程不设置空密码，也不配置免密码 sudo。`wheel` 组用于让该用户在需要时按系统 sudo 策略提权。

输入 `exit` 回到**普通 PowerShell**，以后可以这样进入普通用户：

```powershell
wsl -d AlmaLinux-9.6 -u researcher
```

进入后检查：

```bash
whoami
root-config --version
geant4-config --version
sudo -v
```

全局软件可被普通用户读取和使用；写自己的源码、构建目录时使用 `~/projects`，通常不需要 `sudo`。安装器也为 `/etc/skel` 写入 VS Code Server 环境入口，标准 `useradd -m` 创建的新用户会继承它。

VS Code 扩展按 Linux 用户保存。如果安装器最初给 root 安装了 C/C++ 扩展，切换到 `researcher` 后，需要在该用户的 WSL 窗口中再确认远端扩展已安装，见下一节。

### 7.3 环境变量在哪里生效？

| 配置 | 作用 |
| --- | --- |
| `/etc/profile.d/90-particle-root.sh` | ROOT 命令、Python、头文件、库和 CMake 搜索路径 |
| `/etc/profile.d/91-particle-geant4.sh` | Geant4 路径和物理数据环境变量 |
| `/etc/profile.d/92-particle-garfield.sh` | Garfield++、Python 和 Heed 数据路径 |
| `/etc/ld.so.conf.d/particle-stack.conf` | 系统动态链接器查找三个安装目录的共享库 |
| `~/.vscode-server/server-env-setup` | VS Code WSL Server 启动时加载同一套环境 |
| `/usr/local/bin/hep-env` | 为不启动登录 shell 的命令显式加载环境 |

新的登录 shell 会读取全局配置。对于一个没有加载 shell 启动文件的自动化任务，可以这样执行：

```bash
hep-env root-config --version
hep-env python3 -c 'import ROOT; print(ROOT.gROOT.GetVersion())'
```

如果只想让**当前 Bash 终端**立即重新加载，可执行：

```bash
source /etc/profile.d/90-particle-root.sh
source /etc/profile.d/91-particle-geant4.sh
source /etc/profile.d/92-particle-garfield.sh
```

已经运行的终端、编辑器扩展宿主和调试进程不会被脚本追溯修改。VS Code 的环境入口只在 Server 启动前读取，不能通过“新开一个终端能运行 ROOT”来证明旧扩展宿主已经更新。[VS Code 官方环境入口说明](https://code.visualstudio.com/docs/remote/wsl#_advanced-environment-setup-script)

需要彻底刷新该发行版时，先结束编译和模拟、保存文件并关闭对应 VS Code WSL 窗口，然后在**普通 PowerShell**执行：

```powershell
wsl --terminate AlmaLinux-9.6
wsl -d AlmaLinux-9.6 -u root
```

这会结束该发行版内的所有进程，所以**安装和编译期间不要运行**。普通用户应把第二行的 `root` 换成自己的用户名。

## 8. 在 VS Code 中开发与调试

### 8.1 复制第一个项目到自己的家目录

以下在准备日常使用的 **AlmaLinux 用户终端**执行。首次创建示例工作目录：

```bash
mkdir -p ~/projects
cp -R /opt/particle-stack/examples/all-components ~/projects/all-components
cd ~/projects/all-components
```

安装到 `/opt` 的示例只有 `CMakeLists.txt` 和 `main.cc`，不携带旧的 CMake 构建缓存。再次使用同一项目时，只需要 `cd ~/projects/all-components`，不用重复复制。

源代码同时调用 ROOT 直方图、Garfield++ 气体组分设置和 Geant4 材料查询，适合验证三个库能被同一个 C++ 程序使用。它不是完整的探测器模拟；程序通过不表示任何特定物理模型已经适用于你的研究。

### 8.2 先在终端编译运行

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug -DCMAKE_CXX_STANDARD="$(root-config --cxxstandard)" -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
cmake --build build -- -j"$(nproc)"
./build/all-components
```

这条 CMake 命令没有传入 ROOT、Geant4 或 Garfield++ 的安装路径。成功时输出包含 `ROOT histogram + Garfield++ gas + Geant4 material: passed`。

如果想直接使用 g++，同一目录下可以运行：

```bash
g++ -std="c++$(root-config --cxxstandard)" main.cc -o manual-check -lGarfield -lG4materials -lG4global -lCore -lHist
./manual-check
```

这里没有 `-I` 或 `-L`，但仍写了 `-l...` 库名。编译器不会根据 `#include` 自动猜出应链接哪些库；更复杂的项目建议使用 CMake 导出的目标来处理依赖。

### 8.3 从 Linux 项目目录启动 VS Code

仍在 **AlmaLinux 终端**：

```bash
code .
```

首次连接可能下载对应 Linux 用户的 VS Code Server。打开后：

1. 看左下角，确认显示 **WSL: AlmaLinux-9.6** 或你自定义的发行版名。
2. 按 `Ctrl + Shift + X`，确认 Microsoft 的 **C/C++** 和 **CMake Tools** 在该 WSL 连接中可用。
3. 如果扩展只在 Windows 本地安装，点击对应扩展的“Install in WSL / 在 WSL 中安装”。
4. 通过“终端 → 新建终端”打开终端，运行 `uname -s`，应显示 `Linux`；运行 `which g++`，应指向 Linux 编译器。

也可以在该 WSL 终端执行：

```bash
code --install-extension ms-vscode.cpptools --install-extension ms-vscode.cmake-tools
```

安装器会在找到正常的 Windows VS Code 启动脚本时尝试这一步；如果当时尚未安装 VS Code、启动脚本不可见或后来换了 Linux 用户，需要自己补上。

### 8.4 让代码补全使用 CMake 的信息

打开 `CMakeLists.txt` 和 `main.cc`。按 `Ctrl + Shift + P` 打开命令面板，运行 **CMake: Configure**；如果要求选择工具链，选择 WSL 内的 GCC 11，编译器路径为 `/usr/bin/g++`。

在 VS Code 左侧文件资源管理器中，新建名为 `.vscode` 的文件夹，再在里面新建 `settings.json`，填入：

```json
{
  "cmake.configureOnOpen": true,
  "cmake.configureSettings": {
    "CMAKE_EXPORT_COMPILE_COMMANDS": true
  },
  "C_Cpp.default.configurationProvider": "ms-vscode.cmake-tools"
}
```

这样 C/C++ 扩展从 CMake Tools 获得包含目录和编译设置，通常无需维护一份手写的 `includePath`。本仓库的 [examples/all-components](examples/all-components) 另外提供了 VS Code 配置，可以参考或复制其中的 `.vscode` 文件夹；`/opt` 中的安装示例仅保留 C++ 与 CMake 源文件。

### 8.5 断点调试

先按第 8.2 节使用 `Debug` 编译。在 `main.cc` 中 `histogram.Fill(2.)` 这一行左侧点击，添加断点。可以通过 CMake Tools 选择 `all-components` 目标并运行 **CMake: Debug**。

如果使用仓库示例附带的 `launch.json`，选择 **Debug all-components (WSL)** 后按 `F5`。该配置启动 `${workspaceFolder}/build/all-components`，使用 `/usr/bin/gdb`；它没有额外的自动构建任务，**修改源码后请先重新编译**。

如果你从 `/opt` 复制了纯源码示例，希望同时使用仓库的完整 VS Code 配置，可以在该项目的 **AlmaLinux 终端**执行下面的复制命令。这里假定本仓库仍位于第 1 节的 Windows 目录；如果你已经定制了 `.vscode`，请先查看文件并手动合并配置：

```bash
cp -R /mnt/d/src/wsl-geant4-garfieldpp/examples/all-components/.vscode .
```

调试停在断点时，可查看变量、逐行执行，再继续运行到成功输出。不同 VS Code 版本菜单文字可能略有变化，CMake 配置与调试的基础流程见 [VS Code CMake Tools 文档](https://code.visualstudio.com/docs/cpp/cmake-linux)。

### 8.6 Copilot 与 AI 辅助

Copilot 不是本软件栈的编译依赖。需要时，在这个 **WSL 远程项目窗口**中按 VS Code 的提示完成 GitHub 登录和 Copilot 设置，确认账号有相应使用权限。是否安装、运行在哪一侧，由 VS Code 的扩展机制处理；不要为了补全而另建一套 Windows 编译工具链。[GitHub 官方设置说明](https://docs.github.com/en/copilot/how-tos/set-up/install-copilot-extension?tool=vscode)

本项目没有验证你的 Copilot 登录、套餐权限或实际 AI 请求。即使 ROOT、Geant4 和 Garfield++ 的测试全部通过，也不表示 Copilot 已经登录成功。

## 9. 安装器实际做了什么

Linux 安装器主要分为九个阶段：

| 阶段 | 内容 |
| --- | --- |
| 1 | 检查 Linux、x86_64、WSL 2、AlmaLinux 9 和 WSLg X11 插座 |
| 2 | 刷新 `dnf` 缓存，启用 CRB/EPEL，安装 GCC、CMake、Python、Qt5、图形及科学计算依赖 |
| 3 | 查询 ROOT 兼容正式二进制及 Geant4 最新正式版 |
| 4 | 解压 ROOT，检查 C++ 标准、GDML、Python 版本并运行 ROOT/PyROOT 测试 |
| 5 | 编译 Geant4，启用 GDML、Qt5、OpenGL/X11、多线程和物理数据，运行五个事件 |
| 6 | 编译 Garfield++，使用上述 ROOT，验证 Magboltz 计算与 Heed 数据 |
| 7 | 实际打开 ROOT X11 和 Geant4 Qt/OpenGL 窗口 |
| 8 | 配置固定入口、全局环境、动态库搜索路径和 VS Code Server 环境 |
| 9 | 从干净环境运行功能验证，以非特权用户验证免路径 CMake/g++ 编译 |

Garfield++ 的 CUDA、示例批量编译、文档及上游测试构建选项没有启用；本项目另外运行与本次集成相关的小型功能测试。安装器没有对你的 GPU 计算、复杂几何或研究程序作性能保证。

每次运行会创建新的 `/opt/particle-stack/build.*` 和 `releases` 子目录，保留构建材料供排错；安装成功后通过 `/opt/root` 等固定软链接指向新安装。它不会自动清理以前的构建和安装目录。

脚本还处理了真实部署中遇到的一类 WSL Windows 程序互操作问题：在 systemd 环境中发现缺失的 `WSLInterop` 注册时，安装 `wsl-interop.service`，用 WSL 自身的 `/init` 恢复处理器。该修复在实际发行版重启后验证过。服务是否出现取决于机器是否触发该问题，不要求所有环境都有这个服务。

## 10. 故障排查

### PowerShell 提示禁止运行脚本

确认使用本文的完整启动方式，例如：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\resume-wsl-particle-stack.ps1
```

启用 WSL 的 `enable-wsl.ps1` 要从管理员窗口运行。若电脑由单位策略管理，进程级参数也可能受管理策略约束，需要遵循该电脑的管理要求。

### WSL 启用后仍不能启动

先确认已经**重启 Windows**，而不只是关闭 PowerShell。然后在 PowerShell 运行 `wsl --status` 和 `wsl -l -v`。若错误指向虚拟化，检查 BIOS/UEFI 的硬件虚拟化及 Windows 虚拟机平台状态。不要在 WSL 尚不能实际启动 Linux 时反复运行源码编译脚本。

### 找不到 WSLg 插座，或者 ROOT/Qt 没有窗口

在 **AlmaLinux** 中查看：

```bash
printf 'DISPLAY=%s\nWAYLAND_DISPLAY=%s\n' "${DISPLAY-}" "${WAYLAND_DISPLAY-}"
ls -l /mnt/wslg/.X11-unix/X0
```

主安装器要求这个 X11 插座存在，且会实际测试 GUI。检查 `wsl -l -v` 的 `VERSION` 是 `2`，更新 Windows 显卡驱动和 WSL。不要用 `QT_QPA_PLATFORM=offscreen` 或 `root -b` 的成功结果代替桌面窗口验证。

WSLg 通常会提供显示环境。不要随意把 `DISPLAY` 永久写成 Windows 主机 IP；若之前配置过第三方 X Server 或手工覆盖显示变量，先检查这些旧配置。更多诊断见 [WSLg 官方显示问题说明](https://github.com/microsoft/wslg/wiki/Diagnosing-%22cannot-open-display%22-type-issues-with-WSLg)。

### `code` 找不到，或运行 Windows 程序报 Exec format error

先在 **Windows PowerShell**验证 `code --version`，确认已安装 Windows VS Code、启用 PATH 并重新打开终端。在 **AlmaLinux** 中查看：

```bash
command -v code
ls -l /proc/sys/fs/binfmt_misc/WSLInterop
```

若脚本已经安装互操作修复服务，可检查：

```bash
systemctl status wsl-interop.service --no-pager
```

没有触发修复的机器可能不存在这个服务，这本身不代表故障。还应检查 `/etc/wsl.conf` 是否禁用了 Windows 互操作或 PATH 追加。请先阅读日志，不要把 ROOT、Geant4 重新编译作为 `code` 启动失败的解决办法。

### 终端能编译，VS Code 却找不到头文件

检查左下角是否真的连接到目标 WSL 发行版，并确认 C/C++、CMake Tools 在**当前 Linux 用户**的远端环境中可用。运行 CMake Configure，使用第 8.4 节的配置提供者。

如果 VS Code 在安装器写入环境前已经运行，保存工作后重启该发行版的 VS Code Server，再打开项目。非登录任务也可使用 `hep-env`。不要直接把机器上的版本化 `/opt/particle-stack/releases/...` 路径粘贴进所有工程作为长期修复。

### `import ROOT` 或 `import Garfield` 失败

在新的 **AlmaLinux 终端**查看：

```bash
which python3
python3 --version
root-config --python3-version
printf '%s\n' "${PYTHONPATH-}"
```

本项目使用系统 Python，并检查它与 ROOT 二进制的 Python 版本匹配。若终端激活了 Conda、venv 或其他 Python 环境，应先确认其中的解释器是否与已安装 ROOT 兼容。不要通过在另一个 Python 环境里随意 `pip install ROOT` 混入第二套安装。

### CMake 提示缓存来自另一个源目录

不要复制已有项目的 `build` 目录到另一位置继续使用。安装器交付的 `/opt/particle-stack/examples/all-components` 只包含源文件；你也可以保留有问题的目录，使用一个新的构建目录重试：

```bash
cmake -S . -B build-clean -DCMAKE_BUILD_TYPE=Debug -DCMAKE_CXX_STANDARD="$(root-config --cxxstandard)"
cmake --build build-clean -- -j"$(nproc)"
./build-clean/all-components
```

### 链接时出现 undefined reference

全局路径只能帮助找到库，不能自动补上库名。确认 CMake 中有正确的 `target_link_libraries`，或者 g++ 命令在源文件/目标文件之后列出所需 `-l...`。先用本项目的 `all-components` 示例确认安装正常，再检查自己程序的链接依赖。

### 编译器被 killed，或机器响应很慢

这可能是内存耗尽，需要结合日志确认。在 **AlmaLinux** 中查看：

```bash
free -h
df -h /opt
nproc
```

脚本按当前可见全部 CPU 编译，不自动降低并行度。若日志证实资源不足，可在了解自己电脑资源后调整 WSL 资源分配，或自行修改并行编译命令。不要把失败目录当作已经安装成功，也不要只增加预检查而跳过实际编译。

### 下载失败或 Geant4 数据不完整

在 Linux 的错误日志中定位失败网址，区分 DNS、TLS、代理、HTTP 状态码和磁盘不足。Windows 上仅监听 `localhost` 的代理，在 WSL NAT 环境中未必可直接访问。

`geant4-config --check-datasets` 若报告 `NOTFOUND`，先检查缺失数据和安装日志；Geant4 程序初始化时确实可能用到这些数据。不要通过删除数据检查或忽略程序初始化错误来宣称安装完成。

### 安装失败后是否直接重跑？

先阅读末尾的阶段、退出码和错误日志，解决具体原因，再决定重跑。Windows 导入脚本可以复用符合条件的现有发行版，但 **Linux 安装器不是从上次百分比继续的断点续编工具**：再次运行通常会建立新的构建与安装目录，并重新执行安装步骤。

旧目录会保留，所以重跑前检查空间。不要为了重试直接使用 `wsl --unregister`；该命令会删除发行版中的数据，并不是“重启 WSL”。

## 11. 项目文件与维护

| 文件/目录 | 用途 |
| --- | --- |
| `enable-wsl.ps1` | 管理员执行，启用 WSL，不自动重启 |
| `resume-wsl-particle-stack.ps1` | 普通 Windows 用户执行，导入/复用发行版并调用 Linux 安装器 |
| `run-particle-stack-after-reboot.ps1` | 为上一入口增加部署日志和状态记录 |
| `install-particle-stack.sh` | 完整 Linux 软件栈安装与验证 |
| `verify-no-paths.sh` | 独立重跑非特权用户的免路径编译验证，需要 root/sudo |
| `examples/all-components` | 同时使用 ROOT、Geant4、Garfield++ 的 CMake/C++ 示例及 VS Code 配置 |
| `tests` | 发行选择器和 Windows 启动逻辑等自动化检查 |

如需单独重跑免路径验证，在 **AlmaLinux 的仓库目录**执行：

```bash
sudo bash verify-no-paths.sh
```

若当前已经是 root，可以省去 `sudo`。它安装纯源码示例，在临时目录以 `nobody` 用户开启清空继承环境的登录 shell，分别使用 CMake 和手动 g++ 编译并运行；临时构建目录随后清理。

自动化测试的语法检查、发行目录样例测试和 PowerShell 模拟测试不能代替真实 WSL 的软件编译与 GUI 验证。维护脚本时，应该根据所改行为补充相应实际验证。

升级前先看 `/opt/particle-stack/versions.txt` 并保存自己的项目。新 ROOT 版本可能需要重新编译使用它的 C++ 程序。固定软链接方便日常使用，不代表所有跨版本 ABI 都兼容；ROOT 官方不保证跨版本 ABI 兼容。[ROOT 兼容性说明](https://root.cern/about/versioning/)

## 实测记录与验证边界

2026-09-06，在一套真实的 Windows / WSL 2 环境中完成过以下部署：

| 项目 | 实际结果 |
| --- | --- |
| 初始发行版 | 官方 AlmaLinux 9.6 x64 WSL 镜像 |
| 默认工具链 | GCC 11.5 |
| ROOT | 6.36.06，官方 AlmaLinux 9.6 / GCC 11.5 二进制，C++17 |
| Geant4 | 11.4.2，源码构建，GDML、Qt5、OpenGL/X11、多线程开启 |
| Geant4 数据 | 12 项数据集安装并检查通过 |
| Garfield++ | 官方 `master` 分支，提交前缀 `f706012`，源码构建 |
| ROOT / Python | ROOT 解释器、直方图、PyROOT 与 Garfield Python 导入通过 |
| Geant4 运行 | 使用两个工作线程运行五个真实粒子事件，通过 |
| Garfield++ 运行 | 气体设置、Magboltz 计算和 Heed 数据初始化，通过 |
| 桌面图形 | 实际创建 ROOT X11 和 Geant4 Qt/OpenGL 窗口，通过 |
| 全局可用性 | 非特权用户、干净登录环境下，CMake 不传安装目录，g++ 不传 `-I/-L`，均编译运行通过 |
| WSL 重启 | 重启后 Windows 程序互操作、全局命令及 Python 导入再次验证通过 |
| VS Code | WSL 远端 C/C++、CMake Tools 安装及远端环境检查完成 |
| 公开仓库示例 | 复制到 Linux 临时目录后，以 Debug 配置、不传安装路径完成 CMake 编译运行 |
| GDB 调试 | 公开示例在 `main.cc` 第 10 行断点停住，继续运行后正常退出 |

**这些是实机结果，不是“公开版完整脚本在所有修订结束后，从全新发行版一次无中断跑完”的记录。** 首次部署期间遇到的问题经过定位和修复，随后在该实机上完成相关阶段并做了重启、普通用户和图形界面验证。公开脚本整合了这些修复，但尚未据此宣称完成修订后的全新系统端到端复测。

未验证的内容包括 VS Code 图形界面中的 F5 操作本身、你的 Copilot 账号登录与权限、所有第三方扩展、其他 CPU 架构、全部 Windows/驱动组合、任意研究程序，以及未来上游版本的兼容性。GDB 命令行断点验证不等同于对每个编辑器调试按钮的验证。具体版本、测试输出和失败位置应以自己的安装日志为准。

## 许可证

本仓库的脚本、文档和自行编写的示例采用 [MIT 许可证](LICENSE)。该许可证不替代第三方软件的许可条款；AlmaLinux、WSL、ROOT、Geant4、Garfield++ 及其依赖继续适用各自的许可证。本仓库不打包分发这些项目的镜像、二进制或数据库。

## 官方资料

安装器和文档优先参考各项目官方资料。查找软件本身的使用方法时，可以从下列入口继续：

- [Microsoft：安装 WSL](https://learn.microsoft.com/en-us/windows/wsl/install)
- [Microsoft：导入自定义 Linux 发行版](https://learn.microsoft.com/en-us/windows/wsl/use-custom-distro)
- [Microsoft：WSLg 图形应用](https://learn.microsoft.com/en-us/windows/wsl/tutorials/gui-apps)
- [AlmaLinux：官方 WSL 镜像](https://github.com/AlmaLinux/wsl-images)
- [VS Code：Windows 安装](https://code.visualstudio.com/docs/setup/windows)
- [VS Code：WSL 开发](https://code.visualstudio.com/docs/remote/wsl)
- [ROOT：安装与依赖](https://root.cern/install/)
- [ROOT：全部下载文件](https://root.cern/download/)
- [Geant4：官方下载](https://geant4.web.cern.ch/download/)
- [Geant4：官方文档](https://geant4.web.cern.ch/docs/)
- [Garfield++：官方源码仓库](https://gitlab.cern.ch/garfield/garfieldpp)
- [Garfield++：官方项目网站](https://garfieldpp.web.cern.ch/garfieldpp/)

发现本仓库脚本或说明的问题，可以提交 [Issue](https://github.com/EpochVolatile/wsl-geant4-garfieldpp/issues)。请提供系统/软件版本、执行步骤及与错误相关的日志片段；分享前移除个人路径、账号信息、令牌和代理凭据。
