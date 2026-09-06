# 参与开发

提交问题时，请说明 Windows、WSL、AlmaLinux 和编译器版本，附上失败阶段及相关日志。公开前删除日志中的用户名、私人目录、访问令牌等个人信息。

修改脚本后，先运行本地检查：

```bash
bash -n install-particle-stack.sh
bash -n verify-no-paths.sh
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

在 Windows PowerShell 5.1 和 PowerShell 7 中分别运行：

```powershell
./tests/test-resume-wsl.ps1
./tests/test-windows-wrapper.ps1
```

这两个 PowerShell 测试使用替身，不安装 WSL、不下载软件，也不修改发行版。GitHub Actions 运行上述检查；它不会编译科学软件栈或验证 WSLg 图形界面。

`verify-no-paths.sh` 会使用已安装的软件栈编译和运行示例，应在完成安装的 AlmaLinux WSL 中执行。更改依赖、编译参数、环境变量或 GUI 逻辑时，请说明实际运行了哪些验证以及尚未验证的部分。

`examples/all-components` 与验证脚本中的示例采用相同源码。修改示例时，请同步 `verify-no-paths.sh` 以及安装脚本中的对应示例。不要提交构建产物、安装包或本机日志。

`examples/garfield-field` 是日常操作手册的独立电场/GUI 示例。修改后，在已安装的软件栈中构建，运行其 CTest 和 `--gui-smoke`；普通 GitHub Actions 不提供这套科学软件和 WSLg，因此不会执行该集成验证。
