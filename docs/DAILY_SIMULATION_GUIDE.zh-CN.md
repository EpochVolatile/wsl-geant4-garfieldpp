# 日常仿真操作手册：WSL + VS Code + Geant4 + Garfield++

本文用于**环境已经安装之后**的日常工作：进入正确的 Linux、写 C++、编译测试、调试、打开图形窗口和保存结果。第一次安装请看[安装教程](../README.md)。

## 先记住每天用的几条命令

在 **Windows PowerShell** 进入本机的 Linux：

```powershell
wsl -d AlmaLinux-9.6 -u root
```

然后在 **Linux Bash** 中打开一个已创建的工程：

```bash
cd ~/projects/my-detector
code .
```

在 VS Code 的 **Linux 集成终端**编译运行：

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug -DCMAKE_CXX_STANDARD="$(root-config --cxxstandard)" -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
cmake --build build -- -j"$(nproc)"
./build/all-components
```

`my-detector` 和 `all-components` 对应下文第一个工程；换成自己的工程时，目录和可执行文件名也要相应改变。首次还没有这个目录，请先做[创建工程](#2-创建第一个工程并写代码)。

| 要做的事 | 在哪里执行 | 命令或操作 |
| --- | --- | --- |
| 进入 Linux | Windows PowerShell | `wsl -d AlmaLinux-9.6 -u root` |
| 打开当前 Linux 工程 | Linux Bash | `code .` |
| 编译已配置的工程 | VS Code 的 Linux 终端 | `cmake --build build -- -j"$(nproc)"` |
| 运行已注册的测试 | Linux Bash | `ctest --test-dir build --output-on-failure` |
| Geant4 B1 交互 GUI | B1 的 `build` 目录 | `G4VIS_DEFAULT_DRIVER=OGLSQt ./exampleB1` |
| Geant4 B1 批处理 | B1 的 `build` 目录 | `./exampleB1 smoke.mac` |
| 本文 Garfield 电场 GUI | `garfield-field` 工程根目录 | `./build/garfield-field --gui` |
| ROOT 交互解释器 | Linux Bash | `root -l` |
| 退出 Linux 回到 PowerShell | Linux Bash | `exit` |

## 1. 确认 VS Code 正在使用正确环境

### 当前电脑的约定

以下是 2026-09-06 实机核对的信息；将来升级后以 `versions.txt` 为准。

| 项目 | 当前值 |
| --- | --- |
| WSL 发行版名字 | `AlmaLinux-9.6`，WSL 2 |
| Linux 虚拟磁盘 | Windows 的 `D:\WSL\AlmaLinux-9.6` |
| 当前已配置的用户 | `root`，家目录 `/root` |
| Windows VS Code | `D:\Programs\Microsoft VS Code` |
| 软件入口 | `/opt/geant4`、`/opt/root`、`/opt/garfieldpp` |
| 版本 | Geant4 11.4.2、ROOT 6.36.06、Garfield++ master `f706012` |
| 工具链 | GCC 11.5、ROOT 使用 C++17 |
| 建议工程目录 | `~/projects`，保存在 D 盘上的 Linux 虚拟磁盘内 |

这些软件已经安装，开始新仿真时不用重新执行安装器。`/mnt/d` 直接访问 Windows 文件系统；源码和构建优先放在 Linux 家目录。不要修改 `/opt` 中的公共安装文件来开发自己的程序。

当前流程使用已有的 root。若以后创建了普通 Linux 用户，把 Windows 命令的 `-u root` 换成该用户名；该用户拥有独立的家目录和 VS Code 扩展目录。[普通用户设置](../README.md#72-可选创建日常用户)

### 第一次打开时检查三处

1. VS Code 左下角应显示 **WSL: AlmaLinux-9.6**，或你实际使用的发行版名。
2. 扩展页面中，Microsoft 的 **C/C++**、**CMake Tools** 应安装在该 WSL 连接中。
3. “终端 → 新建终端”中执行：

```bash
uname -s
whoami
pwd
command -v g++ cmake root-config geant4-config
root-config --version
geant4-config --version
```

应看到 `Linux`，工程路径如 `/root/projects/my-detector`，编译器为 Linux 中的 `g++`。如果提示符是 `PS C:\...>`，当前终端仍是 Windows PowerShell。

也可以在 Windows 的 VS Code 中按 `Ctrl+Shift+P`，运行 **WSL: Connect to WSL using Distro...** 并选择 `AlmaLinux-9.6`。从 Linux 工程目录运行 `code .` 更容易确保项目和用户都正确。[VS Code 官方 WSL 说明](https://code.visualstudio.com/docs/remote/wsl)

工程创建后，还可从 **Windows PowerShell**直接打开：

```powershell
code --remote wsl+AlmaLinux-9.6 /root/projects/my-detector
```

此命令按发行版默认用户连接；使用非默认 Linux 用户时，先通过 `wsl -u 用户名` 进入，再运行 `code .`。

## 2. 创建第一个工程并写代码

### 获取配套源码（首次一次）

在 **Linux Bash** 中执行：

```bash
mkdir -p ~/projects
git clone https://github.com/EpochVolatile/wsl-geant4-garfieldpp.git ~/projects/wsl-geant4-garfieldpp
```

如果已经克隆，不要重复 `git clone`。可先用 `git status` 检查本地修改；工作区干净时，在仓库目录运行 `git pull --ff-only` 获取文档和示例更新。

首次创建自己的练习工程：

```bash
mkdir -p ~/projects/my-detector
cd ~/projects/my-detector
cp ~/projects/wsl-geant4-garfieldpp/examples/all-components/CMakeLists.txt .
cp ~/projects/wsl-geant4-garfieldpp/examples/all-components/main.cc .
cp -R ~/projects/wsl-geant4-garfieldpp/examples/all-components/.vscode .
code .
```

以上复制命令只用于新建的练习目录；已有自己代码时不要重复覆盖。显式复制源文件，能避免把其他目录的 `build` 和 `CMakeCache.txt` 一起带过来。若示例目录曾被编译过，创建新工程时也只取源码和配置。

### 工程中每个文件负责什么

```text
my-detector/
├── CMakeLists.txt       # 找依赖、定义可执行文件和链接库
├── main.cc              # C++ 程序入口和当前练习代码
├── .vscode/
│   ├── settings.json    # CMake 与代码补全
│   └── launch.json      # F5 调试入口
└── build/               # 配置后生成；不用手工编辑
```

示例同时使用 ROOT 直方图、Garfield++ 气体组分和 Geant4 材料，验证三个库能用于同一个程序。它还不是完整的探测器仿真。

在 VS Code 左侧打开 `main.cc`，修改代码并按 `Ctrl+S`。例如，把 `histogram.Fill(2.)` 改成 `histogram.Fill(3.)`，重新编译运行，观察自己修改的程序是否正常执行。

`CMakeLists.txt` 中的核心关系如下；这是说明片段，完整工程使用仓库文件：

```cmake
find_package(ROOT REQUIRED COMPONENTS Core Hist)
find_package(Geant4 REQUIRED)
find_package(Garfield REQUIRED)
include(${Geant4_USE_FILE})
add_executable(all-components main.cc)
target_link_libraries(all-components PRIVATE
  Garfield::Garfield ${Geant4_LIBRARIES} ROOT::Core ROOT::Hist)
```

环境负责提供路径，CMake 负责声明程序要使用哪些库。全局安装不意味着编译器会根据 `#include` 自动推导所有链接参数。添加新的 `.cc` 文件时，也要把它加入对应构建目标。

## 3. 编译、运行与测试

### 第一次配置，以及修改构建选项之后

在工程根目录的 **Linux 终端**执行：

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug -DCMAKE_CXX_STANDARD="$(root-config --cxxstandard)" -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
cmake --build build -- -j"$(nproc)"
./build/all-components
```

预期输出包含：

```text
ROOT histogram + Garfield++ gas + Geant4 material: passed
```

`Debug` 用于看变量和断点。普通源文件修改后，保存文件，再执行构建和运行两行即可。新增目标、切换编译器或调整 CMake 设置后重新配置。

准备长时间计算时，可以另建 Release 构建目录，保留调试版本：

```bash
cmake -S . -B build-release -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_STANDARD="$(root-config --cxxstandard)"
cmake --build build-release -- -j"$(nproc)"
./build-release/all-components
```

### 如何判断“测试通过”

| 层次 | 要检查什么 |
| --- | --- |
| 编译与链接 | 构建命令成功，生成目标程序；不是仅仅没有编辑器红线 |
| 最小运行 | 少量事件、固定输入能运行完成；退出码和日志正常 |
| 数值结果 | 能量、轨迹、计数、单位、场强等符合明确的参照或预期 |
| 图形 | 几何、场图或轨迹实际显示；图形正确不代表物理模型已验证 |

在 Bash 中紧接程序运行 `echo $?` 可查看退出码，`0` 通常表示程序报告成功。仍要检查日志：部分示例即使宏命令被拒绝，主程序也可能继续并最终返回 0。

使用 CTest 的项目可运行：

```bash
ctest --test-dir build --output-on-failure
```

只有 `CMakeLists.txt` 注册了测试，这条命令才会执行相应测试。**“No tests were found” 不是仿真通过。** `all-components` 没有注册 CTest，直接运行其程序即可；下文的 `garfield-field` 注册了一个电场数值测试。

## 4. 在 VS Code 中补全与断点调试

先用 Debug 模式构建成功，然后：

1. 按 `Ctrl+Shift+P`，执行 **CMake: Configure**；若要求选择工具链，选择 WSL 的 GCC/G++。
2. 执行 **CMake: Build**，或使用上面的终端构建命令。
3. 在 `main.cc` 的可执行语句左边点一下，添加红色断点。
4. 打开“运行和调试”，选择 **Debug all-components (WSL)**，按 `F5`。
5. 用 `F10` 逐过程、`F11` 逐语句、`F5` 继续；`Shift+F5` 停止调试。

仓库的配置让 C/C++ 扩展使用 CMake Tools 提供的信息，不需要另外填写 Geant4、ROOT、Garfield++ 的绝对 `includePath`。[CMake Tools 官方教程](https://code.visualstudio.com/docs/cpp/cmake-linux)

调试配置中的三个值需要与实际程序一致：

```json
{
  "program": "${workspaceFolder}/build/all-components",
  "args": [],
  "cwd": "${workspaceFolder}"
}
```

这只是已有 `launch.json` 中的关键字段，不能单独代替完整文件。换项目时，修改可执行文件名及参数。`cwd` 决定宏文件、输入数据、相对路径输出从哪里查找。

本仓库的 `launch.json` 没有自动构建任务，**修改代码后要先保存并构建，再按 F5**。断点灰色或不命中时，先检查是否启动了旧程序、Release 程序或另一构建目录。

## 5. Geant4：从官方 B1 开始运行仿真与 GUI

### 创建自己的 B1 副本

在 **Linux Bash** 中首次执行：

```bash
mkdir -p ~/projects
cp -R /opt/geant4/share/Geant4/examples/basic/B1 ~/projects/geant4-b1
cd ~/projects/geant4-b1
cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug -DCMAKE_CXX_STANDARD="$(root-config --cxxstandard)" -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
cmake --build build -- -j"$(nproc)"
code .
```

这里复制的是安装目录中的官方示例源码。已有 `geant4-b1` 工程时直接进入，不再重复复制。B1 是 Geant4 官方 basic 示例；其源文件和说明见[官方目录](https://github.com/Geant4/geant4/tree/v11.4.2/examples/basic/B1)。

主要修改位置：

| 文件 | 用途 |
| --- | --- |
| `src/DetectorConstruction.cc` | 材料、几何体、位置和尺寸 |
| `src/PrimaryGeneratorAction.cc` | 初级粒子源及其生成行为 |
| `src/SteppingAction.cc` | 逐步处理、能量沉积等 |
| `src/EventAction.cc` | 单事件统计 |
| `src/RunAction.cc` | 一次 run 的汇总 |
| `exampleB1.cc` | 初始化物理列表、运行管理器、可视化和 UI |

修改 C++ 后重新构建；只调整运行宏时通常不用重新编译。

### 先跑 5 个事件的批处理

在 **B1 工程根目录的 Linux 终端**创建运行宏：

```bash
cat > build/smoke.mac <<'MAC'
/control/verbose 1
/run/verbose 1
/event/verbose 0
/tracking/verbose 0
/run/numberOfThreads 2
/random/setSeeds 12345 67890
/run/initialize
/gun/particle gamma
/gun/energy 6 MeV
/run/beamOn 5
MAC
cd build
./exampleB1 smoke.mac
```

检查日志中的 **Global Run** 汇总和 5 个事件。线程输出中的局部事件数量可能不同，应看全局结果。日志还应没有找不到宏文件、命令拒绝或 fatal exception 等错误。这个例子用于验证运行流程，并不代表你最终研究所需的物理设置。

### 打开真正可交互的 Qt / OpenGL 窗口

仍在 **B1 的 `build` 目录**：

```bash
G4VIS_DEFAULT_DRIVER=OGLSQt ./exampleB1
```

没有宏文件参数时，B1 进入交互模式。它会读取构建目录的 `init_vis.mac`、`vis.mac`，显示几何与 Qt 界面。**不要运行 `./exampleB1 --gui`**：官方 B1 会把 `--gui` 当成宏文件名。

在 **Geant4 窗口自己的命令输入栏**中输入以下命令；不是在 Bash 里输入：

```text
/gun/particle gamma
/gun/energy 6 MeV
/vis/scene/endOfEventAction accumulate
/run/beamOn 5
```

使用图形窗口的工具调整视角、缩放、查看几何与轨迹。先用少量事件检查显示，批量统计时改用宏文件运行。关闭主窗口退出交互会话。

如果只想快速检查本机 Geant4 GUI 能否打开，可以在任意已加载环境的 Linux 终端运行：

```bash
/opt/particle-stack/bin/g4-check --gui
```

这是安装器提供的检查程序，几秒后自动关闭；`--gui` 是它自己的选项，与官方 B1 的参数规则不同。[Geant4 可视化文档](https://geant4.web.cern.ch/documentation/dev/bfad_html/ForApplicationDevelopers/Visualization/visualization.html)

### 在 VS Code 中调试 B1

可用 CMake Tools 选择 `exampleB1` 目标调试。若自己建立 `launch.json`，沿用前面 `cppdbg` 配置，将关键字段改为：

```json
{
  "program": "${workspaceFolder}/build/exampleB1",
  "args": ["smoke.mac"],
  "cwd": "${workspaceFolder}/build"
}
```

上面调试批处理；GUI 模式把 `args` 改成 `[]`，并在完整调试配置中增加 `"environment": [{"name": "G4VIS_DEFAULT_DRIVER", "value": "OGLSQt"}]`。保留 `cwd` 指向 `build`，否则可能找不到可视化宏。

## 6. Garfield++：电场测试和可交互 GUI

Garfield++ 是库，通常编写自己的可执行程序。它的场图、漂移线等可视化由 `ViewField`、`ViewDrift` 等类配合 ROOT 绘图，不是输入一个通用 `garfield` 命令启动整套软件。[Garfield++ 用户手册](https://garfieldpp.web.cern.ch/doxygen/UserGuide.pdf)

本仓库附有 [garfield-field 示例](../examples/garfield-field)：在相距 2 mm 的两块平行板之间施加 1000 V 电压，检查中心场强与电位，并绘制电位图。它只验证静电场和绘图，没有计算电子漂移、雪崩或读出信号。

首次创建工作副本，在 **Linux Bash** 执行：

```bash
mkdir -p ~/projects/garfield-field
cd ~/projects/garfield-field
cp ~/projects/wsl-geant4-garfieldpp/examples/garfield-field/CMakeLists.txt .
cp ~/projects/wsl-geant4-garfieldpp/examples/garfield-field/main.cc .
cp -R ~/projects/wsl-geant4-garfieldpp/examples/garfield-field/.vscode .
code .
cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug -DCMAKE_CXX_STANDARD="$(root-config --cxxstandard)"
cmake --build build -- -j"$(nproc)"
```

### 不开窗口，先做数值检查

```bash
./build/garfield-field --batch
ctest --test-dir build --output-on-failure
```

预期检查通过，中心输出约为：

```text
Uniform-field check passed: Ey=-5000 V/cm, V=-500 V
```

### 打开 GUI

```bash
./build/garfield-field --gui
```

会出现 ROOT 绘图窗口，显示两块板之间的电位分布。程序保持运行，关闭画布退出。在 VS Code 中选 **Garfield field GUI (WSL)** 后按 F5，可在调试器中运行同一程序；仍需先构建。

想检查窗口可以打开并自动退出：

```bash
./build/garfield-field --gui-smoke
```

此选项几秒后自动结束；这是配套示例定义的选项，不是所有 Garfield++ 程序的通用接口。

打开 `main.cc` 可看到几段职责清楚的代码：`SetComposition` 设置气体，`AddPlaneY` 定义电极，`ElectricField` 查询场，`ViewField` 画图，`TApplication::Run` 保持图形事件循环。修改电压或几何尺寸后，需要同步修改测试的解析参照值，不能仅把失败检查删掉。

## 7. ROOT 窗口和仿真结果

在 Linux 终端运行：

```bash
root -l
```

看到 `root [0]` 后，输入 **ROOT C++ 命令**：

```cpp
auto c = new TCanvas("c", "Simulation results", 800, 500);
auto h = new TH1D("h", "Demo;Value;Entries", 100, -4, 4);
h->FillRandom("gaus", 10000);
h->Draw();
c->Update();
c->SaveAs("demo.png");
```

这会显示演示直方图，并在启动 ROOT 的当前目录保存 PNG。将来自己的仿真应读取或填充实际结果，替换这段随机演示数据。在 ROOT 提示符输入 `.q` 退出。

没有事件循环的独立 C++ 程序可能画完立刻退出，窗口也随之消失。本文 Garfield GUI 示例用 `TApplication::Run` 保持窗口；单纯设置 `DISPLAY` 并不能让程序自动拥有交互界面。

## 8. 每次正式计算应该留下什么

先用小规模测试，再增加事件数。建议每个计算结果目录包含输入宏/参数、运行日志、软件版本和实际输出文件，例如：

```text
results/run-001/
├── input.mac
├── versions.txt
├── run.log
└── ...你自己的程序生成的输出...
```

以 B1 为例，在其 **build 目录**中选择一个新的结果目录：

```bash
mkdir -p ../results/run-001
cp smoke.mac ../results/run-001/input.mac
cp /opt/particle-stack/versions.txt ../results/run-001/versions.txt
set -o pipefail
./exampleB1 ../results/run-001/input.mac 2>&1 | tee ../results/run-001/run.log
```

`pipefail` 让管道能反映前面程序的失败。B1 默认例子主要向控制台输出 run 统计，不能假定每个示例都会生成 `.root` 文件。自己的程序生成文件时，应明确输出路径，避免重复运行覆盖结果。

Geant4 与 Garfield++ 的协同需要自己设计数据传递；两个库能一起链接，并不会自动完成粒子输运、初级电离、漂移和信号计算。尤其要检查单位转换：Geant4 使用带单位的量（建议写 `value * mm`、`value * MeV`），Garfield++ 常用 cm、ns、eV。[Geant4 单位说明](https://geant4.web.cern.ch/documentation/dev/bfad_html/ForApplicationDevelopers/Fundamentals/unitSystem.html)、[Garfield++ 用户手册](https://garfieldpp.web.cern.ch/doxygen/UserGuide.pdf)

记录随机种子、线程设置、材料/气体、场图与边界条件；不要只保存一张 GUI 截图。

## 9. 快速排错

| 现象 | 先做什么 |
| --- | --- |
| `root-config` 找不到 | 确认在正确 WSL 的登录终端；尝试 `hep-env root-config --version` |
| VS Code 有红线但终端可编译 | 确认 WSL 侧 C++ 扩展、执行 CMake Configure、检查 configurationProvider |
| 找不到宏文件 | 检查 `pwd`、参数和调试配置的 `cwd`；B1 GUI 在 `build` 启动 |
| CMake 提示目录与缓存不一致 | 使用新的构建目录，不复制其他位置的 CMake 缓存 |
| `undefined reference` | 检查 `target_link_libraries`，环境路径不代替库名 |
| F5 没停在断点 | 确认已保存、重编译 Debug，`program` 指向正确程序 |
| 没有 GUI 或刚开就消失 | 检查 WSLg、运行模式和事件循环；自动 GUI 检查本来会退出 |
| 编译器被 killed | 查看错误日志、`free -h` 和 `df -h /opt`，确认是否资源不足 |

在 **Linux** 中检查显示环境：

```bash
printf 'DISPLAY=%s\nWAYLAND_DISPLAY=%s\n' "${DISPLAY-}" "${WAYLAND_DISPLAY-}"
ls -l /mnt/wslg/.X11-unix/X0
```

WSLg 负责把 Linux 窗口显示在 Windows 桌面，不需要为本项目再安装一个第三方 X Server。不要把 `root -b` 或 `QT_QPA_PLATFORM=offscreen` 成功当作桌面 GUI 成功。[Microsoft WSLg 说明](https://learn.microsoft.com/en-us/windows/wsl/tutorials/gui-apps)

对于不启动登录 shell 的任务，可用 `hep-env` 加载全局环境。例如，在 Windows PowerShell 启动一个简单检查：

```powershell
wsl -d AlmaLinux-9.6 -u root --exec /usr/local/bin/hep-env root-config --version
```

如果 VS Code Server 在环境配置之前就已启动，旧进程不会自动获得新变量。只有确有此问题时，先保存文件、结束正在运行的计算并关闭该 WSL 的 VS Code 窗口，再在 **Windows PowerShell** 执行 `wsl --terminate AlmaLinux-9.6`，然后重新连接。此操作会结束该发行版的全部进程，不能在计算过程中使用。

## 10. 给 Copilot 或后续助手的工作上下文

在后续任务中，可以复制以下模板，并填写实际工程和研究目标：

```text
本机已部署 WSL 2 / AlmaLinux-9.6，默认使用 Linux root。
Windows VS Code 通过 WSL 连接开发；源码与构建放在 Linux ~/projects 下。
软件位于 /opt/geant4、/opt/root、/opt/garfieldpp，已配置全局环境和 VS Code Server 环境。
当前版本请读 /opt/particle-stack/versions.txt；C++ 标准请用 root-config --cxxstandard。
请先阅读 docs/DAILY_SIMULATION_GUIDE.zh-CN.md，再检查当前工程的 CMakeLists.txt。
不要为了开始新仿真重复部署环境，也不要直接修改 /opt 中的公共安装。
构建使用 Linux GCC/CMake，按实际程序声明链接目标，无需另写版本化库路径。
新功能先用少量事件/明确数值参照验证；报告实际退出码、关键日志及未验证部分。
需要 GUI 时区分 Geant4 宏/UI 与 Garfield++/ROOT 事件循环，检查运行目录。
当前工程目录：<填写 Linux 绝对路径>
本次研究目标、几何/气体/场、输入输出与期望验证：<填写>
```

Copilot 的账号登录和使用权限需在 VS Code 中确认。本文不把“环境能编译”当作“Copilot 已登录”或“物理模型正确”。

## 本文验证范围

文档的路径和启动器已在本机核对。官方 B1 已从安装源码复制后完成 Debug 构建和 5 个 gamma 事件的批处理；B1 的交互启动参数来自该版本真实源码与可视化宏。安装器的 Geant4 Qt/OpenGL 检查程序此前已打开窗口验证。

配套 Garfield 电场示例已在同一 WSL 中完成 Debug 构建，CTest 电场解析参照检查 1/1 通过；`--gui-smoke` 实际创建 ROOT 画布并自动退出，退出码为 0。VS Code F5 的点击流程本次未操作；其配置引用的编译程序和本机 gdb 已分别验证。

这些检查不代表漂移、雪崩或特定探测器响应已经验证。当前 B1 示例的交互 GUI 启动方式依据实装源码核对，本次只实际运行了 B1 批处理；请按上文启动后观察自己的几何和轨迹。
