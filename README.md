# AI Usage Bar

AI Usage Bar 是一个面向 macOS 的本地优先菜单栏应用，用来集中查看多种 AI 编程工具的用量、订阅额度、余额和成本估算。

它不依赖单独的云端后端：应用优先读取本机客户端留下的会话、日志和数据库；只有在需要官方订阅额度、账户余额或服务端窗口信息时，才会使用本机已有凭据请求对应官方接口。

> 当前项目主要面向个人本机使用。不同客户端的本地文件格式和官方接口可能随产品升级变化，因此面板中的“成本”是估算值，“额度/余额”则会标注其数据来源。

## 功能概览

- 常驻 macOS 菜单栏，点击图标打开仪表盘，右键提供刷新、设置和退出。
- 仪表盘支持今日、昨日、本周、上周、本月、上月、本年七个时间段。
- 两列卡片布局，自动根据当前可用工具数量调整高度；点击“按模型”可以展开模型级明细。
- 显示 Token、输入、输出、缓存读取、缓存命中率、推理 Token、请求次数、Credits、订阅窗口和成本估算等指标。
- 打开仪表盘时自动刷新；后台定时刷新；顶部支持手动刷新。
- 支持多个服务端账户，凭据保存到 macOS 钥匙串。
- 设置窗口支持开机自启。
- 无可用数据的工具不会生成空卡片，而会在底部以小字列出。
- 成本估算按模型、输入/输出/缓存 Token 以及适用的时间段价格计算；人民币价格以人民币显示。

## 支持的工具与数据来源

| 工具 | 本地数据 | 官方/服务端数据 | 主要展示内容 |
| --- | --- | --- | --- |
| Codex | `~/.codex/sessions`、`~/.codex/archived_sessions` | ChatGPT 后端 `wham/usage` 订阅窗口 | Token、请求、模型、输入/输出/缓存、成本估算、5 小时/周额度 |
| 千问办公 | `~/.qwenworkcn/projects` 和兼容日志目录中的 JSONL | QwenWork `account-context` | 请求、会话、活跃时长、模型、订阅/加购/共享 Credits |
| WorkBuddy | `~/.workbuddy/projects` JSONL 和 `~/.workbuddy/logs` 积分流水 | 本机账户信息 | Token、输入/输出、缓存命中、推理、Credits、模型、请求和成本估算 |
| DeepSeek Harness | `~/.dsh/sessions` 中的 `.jsonl.zstd`，或 Tokei 缓存 | — | Token、输入/输出、缓存读写、推理、请求、模型、人民币成本 |
| TraeWork CN | Trae CN SQLCipher 数据库及本机兼容日志 | Trae CN 套餐/额度接口 | Token、请求、模型、Credits/额度和服务端状态 |
| MiniMax Code | `~/.minimax/v2/sqlite/runtime-state.sqlite` 及兼容日志 | MiniMax coding plan 接口 | Token、输入/输出、缓存读写、推理、请求、模型、成本和 5 小时/周额度 |

### 数据来源原则

每个指标都带有来源：

- **服务端**：官方额度、套餐或余额接口返回的数据。
- **本地日志**：从客户端本机日志或会话数据库聚合的数据。
- **本机缓存**：官方接口失败时保留的最近一次成功结果，避免仪表盘瞬间清空。
- **未读取**：本机没有对应文件、凭据或字段无法可靠解析。

如果产品只提供 Credits、请求次数或订阅百分比，而没有公开 Token 计费规则，应用不会把 Credits 强行换算成 Token 或美元成本。

## 成本估算口径

成本估算只用于横向观察，不等同于账单。计算时优先读取本机 Tokei 价格表：

```text
~/.tokei/pricing.json
~/.tokei/pricing_overrides.json
```

价格表不可用时，应用使用源代码中的保守内置价格和模型别名映射。覆盖表优先级高于内置值，适合个人根据官方价格更新。

基本计算形式为：

```text
成本 ≈ 未命中输入 Token × 输入单价
     + 缓存读取 Token × 缓存读取单价
     + 缓存写入 Token × 缓存写入单价
     + 输出 Token × 输出单价
```

其中，未命中输入 Token 会从输入总量中扣除缓存读取/写入部分，避免重复计费。对于明确存在长上下文价格变化的模型，适配器会按该模型的规则应用长上下文倍率。

特殊口径：

- Codex Auto Review 映射到 `GPT-5.3-Codex` 价格。
- DeepSeek Harness 按 DeepSeek 官方人民币峰谷价格和北京时间计算，仪表盘显示 `¥`。
- WorkBuddy 会根据实际日志中的模型名匹配 Kimi/Hy 系列价格，并优先使用本机 Tokei 价格表。
- MiniMax Code 使用本地模型用量与 MiniMax 官方 Token 价格估算；Token Plan 的实际扣减以 MiniMax 服务端额度为准。
- QwenWork、TraeWork CN 的 Credits/套餐额度保留原始单位，不把订阅积分冒充 API 成本。

## 隐私与安全

- 所有本地日志解析、去重和聚合都在本机完成。
- 应用不会保存提示词、代码正文或请求内容，只保留必要的统计缓存。
- 手动添加的 Access Token/API Key 保存于 macOS 钥匙串，不写入项目目录。
- 只有读取官方余额/额度时，才会向对应官方接口发起 HTTPS 请求。
- QwenWork 的加密 `auth-v2.dat` 不会被应用绕过解密；未明确提供的凭据不会被猜测。
- TraeWork 的 SQLCipher 解密密钥需要用户显式配置，应用不会尝试从 Trae 进程或钥匙串提取密钥。

## 环境要求

- macOS 13 或更高版本。
- Swift 5.9 或更高版本。
- 当前构建脚本默认生成 Apple Silicon (`arm64`) 应用。
- 项目只使用系统框架：SwiftUI、AppKit、Combine、Security、ServiceManagement。
- TraeWork 本地明细可选依赖 `sqlcipher`。
- DeepSeek Harness 压缩日志读取需要本机 `zstd`；如果已有 Tokei 缓存，也可以使用缓存文件。

## 编译与运行

克隆项目后，在项目根目录执行：

```sh
swift run AIUsageBar
```

生成可双击打开的菜单栏应用包：

```sh
bash scripts/build-app.sh
open dist/AIUsageBar.app
```

脚本会尝试使用 SwiftPM Release 构建；如果当前 SwiftPM 与系统 SDK 的小版本不匹配，会回退到本机 `swiftc` 直接编译，然后生成并签名 `dist/AIUsageBar.app`。

只做静态类型检查：

```sh
xcrun swiftc \
  -typecheck \
  -module-cache-path /private/tmp/AIUsageBarSwiftModuleCache \
  -target arm64-apple-macosx13.0 \
  -sdk "$(xcrun --show-sdk-path)" \
  Sources/AIUsageBar/*.swift
```

## 配置凭据

通常不需要手动配置：应用会尝试读取已安装客户端的本地登录态。需要显式提供凭据时，可以通过仪表盘设置窗口添加账户，或使用以下环境变量：

| 环境变量 | 用途 |
| --- | --- |
| `QWENWORK_ACCESS_TOKEN` | QwenWork 官方 Credits 接口 |
| `MINIMAX_API_KEY` | MiniMax coding plan 额度接口 |
| `AIUSAGEBAR_TRAE_KEY` | TraeWork CN SQLCipher 数据库密钥 |
| `TOKEN_MONITOR_TRAE_KEY` | TraeWork 兼容的备用数据库密钥变量 |

TraeWork CN 的密钥应为 64 位十六进制字符串，也可以保存到：

```text
~/Library/Application Support/AIUsageBar/trae-key.json
```

示例格式：

```json
{
  "key": "在本机配置的64位十六进制密钥"
}
```

不要把真实 Token、API Key、数据库密钥或本机日志提交到 GitHub。

## 设置与账户

点击仪表盘右上角齿轮，或右键点击菜单栏图标后选择“账户设置…”：

1. 在“应用设置”中启用或关闭开机自启。
2. 在“添加服务端账户”中选择产品，填写账户名称和 Access Token/API Key。
3. 已添加账户的凭据保存在 macOS 钥匙串，账户列表元数据保存在：

   ```text
   ~/Library/Application Support/AIUsageBar/accounts.json
   ```

4. 删除账户只会删除 AI Usage Bar 保存的账户配置，不会删除对应客户端的本地数据。

## 项目结构

```text
.
├── Package.swift                 # SwiftPM 包定义
├── Resources/Info.plist          # 菜单栏应用信息与 LSUIElement 配置
├── scripts/build-app.sh          # Release 构建、打包和签名
├── Sources/AIUsageBar/
│   ├── AppModel.swift             # 刷新调度、并发读取与快照状态
│   ├── Models.swift               # 工具、指标、时间窗口和卡片模型
│   ├── Providers.swift            # 各工具 Provider 与服务端额度读取
│   ├── CodexUsage.swift           # Codex 会话、额度和价格计算
│   ├── QwenWorkUsage.swift        # 千问办公 JSONL 统计
│   ├── WorkBuddyUsage.swift       # WorkBuddy JSONL/积分流水统计
│   ├── DeepSeekHarnessUsage.swift # DeepSeek Harness 压缩日志统计
│   ├── MiniMaxCodeUsage.swift     # MiniMax Code SQLite 统计
│   ├── TraeWorkUsage.swift        # TraeWork CN SQLCipher 统计
│   ├── QwenWorkQuota.swift         # 千问办公官方 Credits
│   ├── LocalData.swift             # 本地 JSON、JSONL 和字段兼容解析
│   ├── Paths.swift                 # 各客户端本地路径
│   ├── DashboardViews.swift        # 仪表盘界面
│   ├── Views.swift                 # 菜单栏与设置界面
│   ├── StatusBarController.swift  # 状态栏图标、面板和右键菜单
│   └── SettingsWindowController.swift # 显式设置窗口
└── README.md
```

每个工具的 Provider 都应该返回统一的 `ProviderSnapshot`，把“数据获取”和“界面展示”分开。新增工具时，通常需要补充路径、扫描器、Provider、展示颜色/图标以及 `ProviderID.trackedCases` 顺序。

## 刷新与容错策略

应用使用并发 Provider 扫描：一个服务端接口变慢不会阻塞其他本地数据源。刷新期间如果再次点击刷新，会合并为一次后续刷新，避免重复扫描。

初次读取全部失败时会自动重试；单个服务端请求失败时，如果之前有成功结果，则保留最近一次可用的缓存；本地日志扫描使用文件大小和修改时间缓存，避免每次打开仪表盘都重新解析全部历史记录。

## 已知限制

- 各产品的“额度”“Credits”“请求次数”和“Token”不是同一种计量单位，不能直接横向比较。
- 本地客户端升级后可能改变 JSONL、SQLite、SQLCipher 或日志字段；无法可靠解析时会显示“暂不可用”，而不是猜测数字。
- QwenWork 官方额度接口需要有效 Access Token；加密本地登录态不会被强行解密。
- TraeWork CN 的 Token 明细依赖当前数据库结构和用户提供的 SQLCipher 密钥。
- 服务器返回的订阅额度可能与本地会话日志存在时间差，仪表盘会分别标注来源。
- 公开发布前建议补充正式的应用签名、Notarization、发布包和许可证。

## 贡献建议

提交新的适配器或修复时，请尽量同时提供：

- 本地文件样例的脱敏字段结构，而不是原始日志内容。
- 数据来源和去重规则。
- 时间窗口、缓存命中率、成本或 Credits 的计算公式。
- 无数据、字段缺失、接口失败时的预期显示。
- 至少一次 `swiftc -typecheck` 或完整打包验证。

请不要提交个人日志、Token、API Key、钥匙串导出、数据库文件或由这些文件生成的统计缓存。

## 许可证

当前仓库尚未附带正式开源许可证。若要公开发布或接受外部贡献，请先根据项目维护者的意愿补充许可证文件。
