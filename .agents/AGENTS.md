# OpenWRT-CI Build & Dependency Rules

## 1. 编译期磁盘防爆原则 (Build-Time Disk Space Guard)
- ** Runner 极限空间清理**：每次 CI 编译前必须清理 GitHub Actions 预装的无用软件（含 `.NET`, `Android SDK`, `GHC`, `CodeQL`, `Powershell`, `Swift`, `Chromium`, `Boost`, `JVM`, `Docker/Containerd cache`, `Pipx`, `Vcpkg`, `Node_modules`），确保虚拟机保持 60GB+ 可用空闲。
- **避免重型 GUI/C++ 依赖**：严禁在默认配置中引入 `Qt6` (`qt6base`, `qt6tools`), `rblibtorrent` 等巨型 C++ 框架。
- **Golang 模块代理加速**：始终在构建阶段配置 `export GOPROXY=https://proxy.golang.org,direct`。

## 2. 严格依赖与变体审计原则 (Strict Dependency & Variant Audit)
- **eBPF (大鹅 dae) 构建规范**：必须安装 Host 端 `clang`, `llvm`, `lld` 工具链，必须同步引入 `v2ray-geodata` 规则库，且必须配置全套 BPF/BTF 内核标志 (`CONFIG_BPF_TOOLCHAIN_HOST=y`, `CONFIG_KERNEL_DEBUG_INFO_BTF=y`)。
- **变体裁切与避坑规则**：对于存在废弃依赖的包变体（如 `avahi` 的 `dbus` 变体依赖缺失的 `libdaemon`），必须显式禁用该变体 (`avahi-dbus-daemon=n`) 并启用稳定变体 (`avahi-nodbus-daemon=y`, `umdns=y`)。
- **同名包碰撞预防**：开启 `dnsmasq-full=y` 时，必须显式禁用基础版 `dnsmasq=n`。
- **第三方仓库提取模式**：使用 `Packages.sh` 脚本提取多包仓库（如 `fw876/helloworld`）时，确保使用正确的解压模式（`"name"` 模式）。
