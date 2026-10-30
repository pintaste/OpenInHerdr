# OpenInHerdr

[English](./README.md) | [中文](./README-zh.md)

一个极简的 macOS 访达工具栏小程序：点一下，就在 [Herdr](https://herdr.dev) 里打开访达当前所在的目录。

> 参照 [OpenInOtty](https://github.com/pintaste/OpenInOtty) 制作，而 OpenInOtty 的灵感来自 [OpenInTerminal-Lite](https://github.com/Ji4n1ng/OpenInTerminal)。

![macOS 12+](https://img.shields.io/badge/macOS-12%2B-blue) ![Swift 5](https://img.shields.io/badge/Swift-5-orange) ![License MIT](https://img.shields.io/badge/license-MIT-green)

---

## 功能

- **一键打开**：点工具栏图标，Herdr 就在访达当前路径打开
- **路径判断**
  - 有选中项 → 用选中项（选的是**文件**就用它所在的**文件夹**）
  - 没有选中 → 访达最前面窗口的文件夹
  - 没有可用窗口 → 桌面
- **Herdr 打开方式**（走 Herdr 自带的 `herdr-app` 命令行，就是 App 本身的可执行文件）
  - 已经有这个文件夹的空间 → 在里面新开一个标签页（`do tab.new --space <id> --folder <路径>`），并切到这个空间
  - 否则 → 在这个文件夹新建一个空间（`do space.new --folder <路径>`）
  - Herdr 窗口没开 → 先用 Launch Services 启动 Herdr，最多等 15 秒窗口就绪，再执行上面的步骤
- **按 bundle id 找 Herdr**（`dev.herdr.app`），找不到再试 `~/Applications/Herdr.app` 和 `/Applications/Herdr.app`
- **出错会提示**：失败时弹 `NSAlert`（附上 Herdr 返回的错误），不会悄无声息
- **没有菜单栏 / 程序坞图标**：`LSUIElement = true`，打开后立刻退出

---

## 环境要求

| 项目 | 版本 |
|---|---|
| macOS | 12.0 Monterey 及以上 |
| Xcode | 15 及以上 |
| [Herdr](https://herdr.dev) | 已在 0.1.9（herdr-core 0.1.14）上测试 |

---

## 安装

### 从源码编译

```bash
cd openinherdr
xcodebuild -project OpenInHerdr.xcodeproj \
           -scheme OpenInHerdr \
           -configuration Release \
           -derivedDataPath build \
           build
cp -R build/Build/Products/Release/OpenInHerdr.app /Applications/
```

### 加到访达工具栏

按住 **⌘（Command）**，把 `/Applications/OpenInHerdr.app` 拖到访达窗口的工具栏上。

第一次点图标时，系统会问是否允许 OpenInHerdr 控制访达，点 **允许**。

### 重置权限（不小心点了拒绝）

```bash
tccutil reset AppleEvents com.local.OpenInHerdr
```

---

## For AI agents / LLMs（给 AI 助手看的）

在用户的 Mac 上安装、验证或排查 OpenInHerdr 时参考这一节。请直接用下面的命令，不要自己编别的 bundle id。

### 关键信息

| 项目 | 值 |
|---|---|
| Bundle ID | `com.local.OpenInHerdr` |
| 安装位置 | `/Applications/OpenInHerdr.app` |
| Herdr bundle ID | `dev.herdr.app` |
| 查找 Herdr | `NSWorkspace.urlForApplication(withBundleIdentifier: "dev.herdr.app")`，否则 `~/Applications/Herdr.app`，再否则 `/Applications/Herdr.app` |
| Herdr 命令行 | `<Herdr.app>/Contents/MacOS/Herdr`（和 `herdr-app` 是同一个程序，通过 `~/.config/herdr-app/herdr-app.sock` 控制窗口） |
| 源码 | `OpenInHerdr/main.swift`（单文件） |
| 界面类型 | `LSUIElement = true`（无程序坞 / 菜单栏图标） |

### 安装步骤

```bash
mdfind "kMDItemCFBundleIdentifier == 'dev.herdr.app'" | head -1   # 有没有装 Herdr
xcodebuild -version
xcodebuild -project OpenInHerdr.xcodeproj -scheme OpenInHerdr \
           -configuration Release -derivedDataPath build build
cp -R build/Build/Products/Release/OpenInHerdr.app /Applications/
```

**只能人来做的一步**：按住 ⌘ 把 `/Applications/OpenInHerdr.app` 拖到访达工具栏，点一次，在“自动化 → 访达”的弹窗里选 **允许**。

### 验证

```bash
HERDR="$(mdfind "kMDItemCFBundleIdentifier == 'dev.herdr.app'" | head -1)/Contents/MacOS/Herdr"
"$HERDR" --version

# 不经过访达：传一个路径参数会跳过访达查询（不会弹自动化权限）
mkdir -p /tmp/oih-check
/Applications/OpenInHerdr.app/Contents/MacOS/OpenInHerdr /tmp/oih-check
"$HERDR" ls        # 应该能看到 folder 为 /tmp/oih-check 的空间
```

### 运行逻辑（排查用）

1. 路径：有命令行参数（不以 `-` 开头）就用它（文件取所在目录）；否则用 ScriptingBridge 的 `finderPath()`（选中项 → 最前窗口 → `~/Desktop`）。
2. 找到 Herdr.app（bundle id → `~/Applications` → `/Applications`）和它的可执行文件。
3. `Herdr ls` 要能返回 JSON；返回 “no Herdr window” 就 `open -a <Herdr.app>`，每 0.25 秒查一次，最多 15 秒。
4. `ls` 里有本机空间的 folder 和路径一致（会解析符号链接，比如 `/tmp` = `/private/tmp`）→ `do tab.new --space <id> --folder <路径>` 加 `do space.select --id <id>`；否则 `do space.new --folder <路径>`。
5. 激活 Herdr 后退出码 0；失败弹 `NSAlert`，退出码 1。

### 注意事项

- 路径一律作为独立的 `Process` 参数传，不要拼进 `sh -c` 或 AppleScript。
- 要提醒用户自己 ⌘ 拖到工具栏，AI 助手跳不过这一步。
- 改 bundle id 时要同步改 `Info.plist`、entitlements 和本文档。
- 不要提交 `build/`、`DerivedData/`、`.DS_Store`。

---

## 工作原理

```
点工具栏图标
     │
     ▼
 路径 = 参数 ?? finderPath()   （选中项 → 窗口 → 桌面；文件取上级目录）
     │
     ▼
 找到 Herdr.app → Contents/MacOS/Herdr
     │
     ▼
 窗口开着吗？(Herdr ls) ── 没有 ──► open -a Herdr.app，最多等 15 秒
     │
     ▼
 有这个文件夹的空间？── 有 ──► do tab.new --space <id> --folder <路径>
     │                         do space.select --id <id>
     没有
     ▼
 do space.new --folder <路径>
     │
     ▼
 激活 Herdr / 出错弹窗 → 退出
```

**为什么用 `perform(NSSelectorFromString:)`，而不是 ScriptingBridge 协议？** Swift 的 `@objc optional` 协议调用会先查 `respondsToSelector:`，而 ScriptingBridge 私有的 `SBScriptableApplication` 对转发的 Apple Event 方法返回 `false`，结果调用静默返回 `nil`，权限弹窗也不会出现。`perform()` 跳过了这个检查。

---

## 项目结构

```
openinherdr/
├── OpenInHerdr.xcodeproj/
├── OpenInHerdr/
│   ├── main.swift                 # 全部逻辑
│   ├── Info.plist                 # LSUIElement=true、权限说明
│   ├── OpenInHerdr.entitlements   # Apple Events 权限，不开沙盒
│   └── Assets.xcassets/           # App 图标
├── scripts/
│   └── make_app_icon.py           # 从 Herdr.app 重新生成图标（需要 Pillow）
├── README.md
└── README-zh.md
```

---

## 常见问题

**点了图标没反应**：看看 **系统设置 → 隐私与安全性 → 自动化** 里 OpenInHerdr → 访达有没有打开；或者运行 `tccutil reset AppleEvents com.local.OpenInHerdr` 后再点一次。

**打开的是桌面而不是当前文件夹**：需要有一个没最小化的访达窗口，或者选中了某个文件 / 文件夹。

**弹出“Herdr 窗口没有就绪”**：Herdr 打开窗口超过了 15 秒（比如启动时在装更新），等窗口出来后再点一次。

**为什么新建了空间而不是标签页**：只有当某个空间的文件夹正好是这个文件夹时才会加标签页，否则新建空间。

---

## 许可证

MIT，见 [LICENSE](LICENSE)。
