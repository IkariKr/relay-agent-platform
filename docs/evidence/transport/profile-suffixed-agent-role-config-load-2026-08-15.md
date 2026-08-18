# Profile-suffixed Agent Role Config-load Probe — 2026-08-15

> 状态：**配置加载通过；native child runtime 未在本探测中验证**
> 调用边界：零模型调用、零第三方 provider 计费。使用临时 `CODEX_HOME`，未使用用户 credential。

## 目的

验证 onboarding 新增的多 profile role 命名：

```text
<worker-id>--<profile-id>
```

是否至少能被当前 Codex 配置加载器接受。此前 B4 paid native smoke 验证的是：

```toml
[agents.deepseek-v4-flash]
```

并未覆盖 profile 后缀形态。

## 环境

- Codex CLI：`codex-cli 0.147.0`
- Host：Windows / pwsh
- 临时 role：`deepseek-v4-flash--profile-test`
- 临时 agent overlay：`model_provider = "openai"`、`sandbox_mode = "read-only"`

## 探测

临时 `config.toml`：

```toml
[agents.deepseek-v4-flash--profile-test]
description = "role syntax probe"
config_file = "<temporary>/agent.toml"
```

执行：

```text
codex doctor --json --no-color
```

关键结果：

```text
config.load.status = ok
config.load.summary = config loaded
config.toml parse = ok
```

`doctor` 的 overall status 因临时 `CODEX_HOME` 没有 auth credential 而为 fail，这与 role/config 解析无关。该命令还执行了宿主网络可达性诊断，但没有发起模型请求或第三方 provider 付费调用。

## 结论与限制

- `[agents.deepseek-v4-flash--profile-test]` 在 codex-cli 0.147.0 的配置加载层可接受；双连字符本身不是当前 config parser blocker。
- 该探测**不能**证明 profile-suffixed role 已通过 `spawn_agent` / child identity / `wait` / cancel 等 B4 runtime 行为。
- P0-4 Codex CLI regression 必须使用 `<worker-id>--<profile-id>` 形态重新跑 native child 验收；完成前，不把旧 `[agents.deepseek-v4-flash]` B4 claim 自动扩展到新 role 命名。
