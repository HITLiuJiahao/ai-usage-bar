# AI Usage Bar

![AI Usage Bar dashboard](assets/dashboard.png)
![AI Usage Bar edge dock](assets/edge-dock.png)

AI Usage Bar is a local-first macOS menu bar application for viewing usage, subscription quotas, balances, and estimated costs from multiple AI coding tools in one place.

The app does not require a separate cloud backend. It primarily reads session files, logs, and databases left by local clients. When official subscription quotas, account balances, or server-side usage windows are needed, it uses the credentials already available on the Mac to call the corresponding official APIs.

> This project is currently intended primarily for personal use on a local Mac. Local file formats and official APIs may change as the supported products evolve. Costs shown in the dashboard are estimates, while quotas and balances are labeled with their data sources.

## Download

Download the latest Apple Silicon (`arm64`) ZIP directly: [AIUsageBar-arm64-release-20260902.zip](https://raw.githubusercontent.com/HITLiuJiahao/ai-usage-bar/agent/fix-workbuddy-usage/dist/AIUsageBar-arm64-release-20260902.zip). Unzip the download, move `AIUsageBar.app` to the Applications folder, and open it by right-clicking **Open** the first time if macOS asks for confirmation.

## Features

- Runs in the macOS menu bar. Click the icon to open the dashboard; right-click for refresh, settings, and quit actions.
- Shows a compact, on-demand usage Dock attached flush to the right edge of the screen, with a broad curved shoulder that blends into the desktop. Click the menu bar indicator or move the pointer to the rightmost edge to wake it; hover a provider to expand its details to the left, and move away to let it collapse. The original full dashboard remains available from the Dock.
- Supports seven time ranges: today, yesterday, this week, last week, this month, last month, and this year.
- Distinguishes the standalone QwenWork client from ZCode and Doubao Work local usage records, and includes OpenCode, Qianwen Office Mode, and DeepSeek Harness local usage.
- Uses a two-column card layout and adjusts its height based on the number of available providers. Click **By Model** to expand model-level details.
- Displays tokens, input, output, cache reads, cache-hit rate, reasoning tokens, request counts, Credits, subscription windows, and estimated costs.
- Uses each supported tool's official brand icon in the Dock and dashboard, with a SF Symbol fallback if an icon resource is unavailable.
- Refreshes automatically when the dashboard opens, on a background timer, or manually from the refresh control at the top.
- Supports multiple server-side accounts, with credentials stored in the macOS Keychain.
- Supports launching automatically at login.
- Lets you edit the relative order of AI tools in the edge Dock from settings; the order is saved locally and is also used by the full dashboard.
- Supports Simplified Chinese (default), English, Japanese, and Korean; the selected interface language applies immediately and is saved locally.
- Providers without usable data do not create empty cards; they are listed in small text at the bottom instead.
- Estimates costs using model-specific input, output, and cache-token prices, including time-window pricing where applicable. CNY prices are displayed in yuan.

## Supported Tools and Data Sources

| Tool | Local data | Official/server-side data | Main metrics |
| --- | --- | --- | --- |
| Codex | `~/.codex/sessions`, `~/.codex/archived_sessions` | ChatGPT backend `wham/usage` subscription windows | Tokens, requests, models, input/output/cache usage, estimated cost, 5-hour and weekly quotas |
| QwenWork | `~/.qwenworkcn/projects` and compatible JSONL log directories | QwenWork `account-context` | Requests, sessions, active time, models, subscription/add-on/shared Credits |
| ZCode | `~/.zcode/cli/db/db.sqlite` (`model_usage`) | — | Tokens, input/output/cache reads, reasoning, requests, sessions, models, and price-based cost estimates |
| Doubao Work | `Default/IndexedDB/chrome_doubaowork-chat_0.indexeddb.leveldb` (`ext_window_usage`), plus `Tea/tea.db` and `sdk_storage/log` (`net_report_dev`) | — | Per-model-call counts with date-correct local activity; token and cost fields are not exposed by the local logs |
| OpenCode | `~/.local/share/opencode/opencode.db` (`message`) | — | Tokens, input/output/cache usage, requests, sessions, models, and price-based cost estimates |
| Qianwen Office Mode | `~/Library/Application Support/Qianwen/qwen-agent` (`thread-events.jsonl`) | — | Tokens, input/output/cache usage, requests, sessions, models, and price-based cost estimates |
| WorkBuddy | JSONL files under `~/.workbuddy/projects` and `~/.workbuddy/logs` | Local account information | Tokens, input/output, cache hits, reasoning, Credits, models, requests, and estimated cost; every JSONL record containing `providerData.rawUsage`, including `function_call` records, counts as one model call |
| DeepSeek Harness | `~/.dsh/sessions` (`.zstd` or Tokei JSONL cache) | — | Tokens, input/output/cache usage, requests, models, and price-based cost estimates |
| MiniMax Code | `~/.minimax/v2/sqlite/runtime-state.sqlite` and compatible logs | MiniMax coding plan API | Tokens, input/output, cache reads/writes, reasoning, requests, models, estimated cost, and 5-hour/weekly quotas |

### Data Source Principles

Every metric carries a data source:

- **Server**: Data returned by an official quota, plan, or balance API.
- **Local logs**: Data aggregated from local client logs or session databases.
- **Local cache**: The most recent successful result retained when an official API fails, so the dashboard does not suddenly become empty.
- **Not read**: The required local file, credential, or field is unavailable or cannot be parsed reliably.

If a product only provides Credits, request counts, or a subscription percentage and does not publish a reliable token-billing formula, the app does not force-convert Credits into tokens or US-dollar costs.

## Cost Estimation

Cost estimates are intended for comparison and monitoring; they are not invoices. The app first looks for local Tokei pricing files:

```text
~/.tokei/pricing.json
~/.tokei/pricing_overrides.json
```

If the pricing files are unavailable, the app uses conservative built-in prices and model aliases. The override file takes precedence over built-in values, allowing users to update prices according to official pricing.

The basic calculation is:

```text
Estimated cost ≈ uncached input tokens × input price
                + cache-read tokens × cache-read price
                + cache-write tokens × cache-write price
                + output tokens × output price
```

Uncached input tokens are calculated by subtracting cache-read and cache-write tokens from the total input where appropriate, avoiding double counting. For models with documented long-context pricing, the adapter applies the model-specific long-context multiplier.

Special cases:

- Codex Auto Review is mapped to `GPT-5.3-Codex` pricing.
- DeepSeek Harness costs use the provider's official CNY peak/off-peak price table when the model and timestamp can be matched.
- WorkBuddy matches the actual model names in its logs to Kimi/Hy model pricing and prefers the local Tokei pricing files.
- WorkBuddy treats `prompt_tokens` as the complete prompt total. Its cache-hit rate is `prompt_cache_hit_tokens / prompt_tokens`; cache hits are not added to input or cost a second time.
- ZCode treats `input_tokens` as the complete prompt total and uses `computed_total_tokens` as the authoritative total. Cache reads are retained as a separate breakdown for hit-rate and cost estimation.
- OpenCode costs prefer a stored message cost and otherwise use the local model price table.
- MiniMax Code estimates cost from local model usage and MiniMax's official token prices. Actual Token Plan deductions are determined by MiniMax's server-side quota.
- QwenWork Credits/plan quotas retain their original units. Subscription Credits are not presented as API costs.
- Qianwen Office Mode costs use public model token prices as estimates rather than official Credits deductions.
- Doubao Work counts the local chat ledger's `ext_window_usage` records, so multiple model calls inside one work task are counted separately. It uses the chat folder date for daily buckets, keeps history in the local cache, and falls back to the task ledger or completion events only when model-usage records are unavailable. The long-lived `/alice/office/tool_local/chunk_stream` local-tool channel is intentionally excluded because it reconnects periodically without representing a new model request. The current local event payload does not expose reliable input/output token fields, so Token and cost are left unavailable instead of estimated from byte sizes.

## Privacy and Security

- Local log parsing, deduplication, and aggregation are performed on the Mac.
- The app does not store prompts, source code, or request bodies. It only retains the statistics needed for the dashboard cache.
- Access tokens and API keys entered manually are stored in the macOS Keychain, not in the project directory.
- The app makes HTTPS requests to an official provider API only when it needs to read balance or quota information.
- The encrypted QwenWork `auth-v2.dat` file is not bypassed or decrypted. Credentials that are not explicitly provided are never guessed.

## Requirements

- macOS 13 or later.
- Swift 5.9 or later.
- The default build script produces an Apple Silicon (`arm64`) application.
- The project uses only system frameworks: SwiftUI, AppKit, Combine, Security, and ServiceManagement.
- Reading compressed DeepSeek Harness logs requires `zstd`. If a Tokei cache is available, the cache can be used instead.

## Build and Run

After cloning the project, run this command from the project root:

```sh
swift run AIUsageBar
```

To generate a double-clickable menu bar application bundle:

```sh
bash scripts/build-app.sh
