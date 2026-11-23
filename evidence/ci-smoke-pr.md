# CI 冒烟记录：测试 PR #2（已关闭，未合入）

目的：在 GitHub Actions 上真跑一次 `.github/workflows/infra-ci.yml`，
验证工作流文件本身没写错（本地只能验证各命令，验证不了 YAML 与
Actions 行为）。PR #2 是临时冒烟 PR，验证完关闭、分支已删，未合入 main。

仓库：AWKN-Lab/clawhunt-3156-infra-ci
PR：https://github.com/AWKN-Lab/clawhunt-3156-infra-ci/pull/2（已关闭，未合并）
分支：test/ci-smoke（已删除；改动只是一行注释，触发 infra/** 路径过滤）

## 第 1 次运行：45261429817（2026-11-23 20:38 UTC）

| 作业 | 结论 | 用时 |
| --- | --- | --- |
| terraform fmt | success | 5s |
| terraform validate (dev) | success | 23s |
| terraform validate (test) | success | 13s |
| terraform validate (prod) | success | 12s |
| tflint (terraform ruleset) | success | 6s |
| checkov security scan | success | 29s |
| terraform plan (dev only) + PR comment | 挂起 | 7m50s 后手动取消 |

问题：plan 作业在 `terraform plan` 步骤卡住 7 分钟以上未返回。
原因：dev 环境没配云凭证，alicloud provider 在凭证/元数据解析上
长时间重试。流水线本身没写错，但缺凭证时应该快速失败而不是挂起。

## 修复

在 plan 步骤前加前置检查 `fail fast if dev credentials are missing`：
`ALICLOUD_ACCESS_KEY` / `ALICLOUD_SECRET_KEY` 为空时直接报错退出，
并提示去 Environment `dev` 配最小权限 RAM 子账号 secrets。
提交：main 上的 `3c73163`（同日合入 smoke 分支重跑）。

## 第 2 次运行：45263011109（2026-11-23 20:47 UTC）

| 作业 | 结论 | 用时 |
| --- | --- | --- |
| terraform fmt | success | 6s |
| terraform validate (dev) | success | 13s |
| terraform validate (test) | success | 10s |
| terraform validate (prod) | success | 10s |
| tflint (terraform ruleset) | success | 5s |
| checkov security scan | success | 22s |
| terraform plan (dev only) + PR comment | failure（预期内） | 8s |

plan 作业在前置检查步骤失败，日志原文：
`::error::dev 环境未配 ALICLOUD_ACCESS_KEY / ALICLOUD_SECRET_KEY，无法 plan。请在仓库 Environment 'dev' 里配最小权限 RAM 子账号的 secrets 后重跑。`

结论：除 plan 外 6 个作业在 GitHub Actions 上全部通过；
plan 作业在无凭证时快速失败、报错明确，属预期行为。
配好 `dev` 环境 secrets 后 plan 作业才能继续跑通（真实 plan、
摘要生成与 PR 评论更新三步尚未在 CI 里跑通过——那需要客户云凭证，
见 README“未做的事”）。
