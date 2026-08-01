# OpenWRT-CI Build & Dependency Rules

> **核心铁律**：**严禁图省事阉割功能、删除依赖或绕过报错**！遇到编译中断或符号缺失，必须追根溯源补齐缺失的源码包与驱动组件，确保固件功能与硬件加速 100% 完整。
> **强制前置规则**：在执行任何 CI 编译任务、修改配置文件、编写 Shell 脚本或调试报错前，必须先复核并严苛遵循项目标准构建链路文档 [openwrt_standard_build_flow.md](file:///.docs/openwrt_standard_build_flow.md)。

## 1. 编译期磁盘防爆原则 (Build-Time Disk Space Guard)
- ** Runner 极限空间清理**：每次 CI 编译前必须清理 GitHub Actions 预装的无用软件（含 `.NET`, `Android SDK`, `GHC`, `CodeQL`, `Powershell`, `Swift`, `Chromium`, `Boost`, `JVM`, `Docker/Containerd cache`, `Pipx`, `Vcpkg`, `Node_modules`），确保虚拟机保持 60GB+ 可用空闲。
- **避免重型 GUI/C++ 依赖**：严禁在默认配置中引入 `Qt6` (`qt6base`, `qt6tools`), `rblibtorrent` 等巨型 C++ 框架。
- **Golang 模块代理加速**：始终在构建阶段配置 `export GOPROXY=https://proxy.golang.org,direct`。

## 2. 严格依赖与变体审计原则 (Strict Dependency & Variant Audit)
- **eBPF (大鹅 dae) 构建规范**：必须安装 Host 端 `clang`, `llvm`, `lld` 工具链，必须同步引入 `v2ray-geodata` 规则库，且必须配置全套 BPF/BTF 内核标志 (`CONFIG_BPF_TOOLCHAIN_HOST=y`, `CONFIG_KERNEL_DEBUG_INFO_BTF=y`)。
- **变体裁切与避坑规则**：对于存在废弃依赖的包变体（如 `avahi` 的 `dbus` 变体依赖缺失的 `libdaemon`），必须显式禁用该变体 (`avahi-dbus-daemon=n`) 并启用稳定变体 (`avahi-nodbus-daemon=y`, `umdns=y`)。
- **同名包碰撞预防**：开启 `dnsmasq-full=y` 时，必须显式禁用基础版 `dnsmasq=n`。
- **第三方仓库提取模式**：使用 `Packages.sh` 脚本提取多包仓库（如 `fw876/helloworld`）时，确保使用正确的解压模式（`"name"` 模式）。

## 3. 依赖图完整性原则 (Dependency Graph Integrity Rule)
- **优先补齐源码而非篡改依赖图**：遇到缺失依赖库时，必须通过 `Packages.sh` 克隆补齐该依赖包的源码，绝不能盲目用 `sed` 强行抹除 `Makefile` 中的 `DEPENDS:=+pkg` 依赖声明。抹除依赖声明会破坏 OpenWRT 的编译拓扑顺序（导致依赖库未先编译进 `staging_dir`，目标包提前编译报错）。
- **严禁虚构 Autoconf/Configure 参数**：严禁在 `Handles.sh` 中擅自注入未经上游 `configure.ac` 验证的构建参数（如不存在的 `--disable-libdaemon`）。遵循 OpenWRT 标准构建链路。

## 4. Alpine `apk-tools` 打包与解耦原则 (APK Packaging & Source Decoupling)
- **版本号格式与下载文件名解耦**：ImmortalWRT 主线使用 Alpine `apk` 打包。对于形如 `0.4.0rc1` 的 RC/Beta 包版本，`apk mkpkg` 必须要求下划线格式（`0.4.0_rc1`）。修补 `PKG_VERSION` 时，**必须同步显式指定 `PKG_SOURCE:=pkg-0.4.0rc1.zip`**，防止 OpenWRT 默认拼错 URL 导致源码包下载 404 失败。

## 5. 高通 NSS 硬件加速功能完整性原则 (Qualcomm NSS HW Acceleration Integrity)
- **严禁阉割加速功能规避报错**：遇到 `qca-nss-ecm` 提示 `nss_rmnet_rx_get_ifnum undefined` 等符号丢失报错时，**严禁通过关闭 `ECM_INTERFACE_RMNET_ENABLE=n` 阉割蜂窝加速**。必须在配置中补齐缺失的高通 NSS RmNet 驱动包（`CONFIG_PACKAGE_kmod-qca-nss-drv-rmnet=y` 与 `CONFIG_PACKAGE_kmod-qca-nss-clients-rmnet=y`），确保硬件加速 100% 全开且编译通过。

## 6. CI 诊断日志推送无损防卡原则 (CI Failure Log Push Reliability)
- **推送前工作区未暂存文件 Stash 隔离**：GitHub Actions 在编译失败推送日志前，必须先执行 `git stash -u 2>/dev/null || true`，清空 OpenWRT 编译过程产生的未暂存修改，确保 `git pull --rebase` 和 `git push origin dev` 100% 成功推送，绝不丢失日志。

## 7. 本地预检验证与线上 CI 加速原则 (Local Validation & CI Acceleration)
- **本地编译定位（快速预检）**：跑本地 Docker 编译的核心目的是**作为前置验证工具（Pre-flight Check）**。通过本地隔离环境预先跑通自动化脚本，提前拦截所有的依赖冲突、Makefile 语法错误及镜像体积超限，为线上编译避坑扫清障碍。
- **线上编译定位（高效产出）**：通过本地脚本 100% 验证无误后再推送，确保 GitHub Actions 线上 CI 能够一次性通关成功，避免在云端盲目试错等待，从而实现**极速、高效的线上云端固件构建与发布**！
