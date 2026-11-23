# ClawHunt #3156 — 会员空间平台 · 基础设施 CI

S2-INFRA-014：给 `infra/**` 写一条 GitHub Actions 流水线，做
`terraform fmt` → 三环境 `validate` → `tflint` → `checkov` 安全扫描 →
只对 dev 做 `terraform plan` 并把摘要写成 PR 评论。**不执行 apply，没有回滚。
prod 不在 CI 里 plan 或 apply。**

报价 $90，净额 $67.50（报价 × 75%）。

## 交付物

| 文件 | 说明 |
| --- | --- |
| `.github/workflows/infra-ci.yml` | 流水线本身（fmt / validate 矩阵 / tflint / checkov / plan+评论） |
| `.tflint.hcl` | tflint 配置（内置 terraform 规则集；见下文“alicloud 规则集”核实） |
| `.checkov.yaml` | checkov 配置：只启用与本单相关的 5 条规则 |
| `checks/sg_no_open_ingress.yaml` | 自定义 checkov 规则 CKV_CUSTOM_ALI_1 |
| `infra/envs/{dev,test,prod}/` | 测试用 .tf（VPC、交换机、安全组、OSS 桶、RDS 实例与账号；全是虚构数据） |
| `scripts/plan_summary.py` | plan JSON → PR 评论（只含数量与资源地址，不含任何属性值） |
| `scripts/comment_upsert.py` | 按 marker 更新或新建评论（AC3 本地验证用，与 workflow 同语义） |
| `tests/` | 四条验收的本地复现脚本 + 含假秘密的 plan 夹具 |
| `evidence/` | 本地实测输出原文与验收 2 截图 |

## 流水线怎么跑

触发：PR 改动 `infra/**`、工作流本身、`.tflint.hcl`、`.checkov.yaml`、
`checks/**` 或 `scripts/plan_summary.py` 时。

| 作业 | 做什么 |
| --- | --- |
| `fmt` | `terraform fmt -check -recursive -diff`，格式不规范即失败 |
| `validate`（矩阵 dev/test/prod） | 各环境 `terraform init -backend=false` + `terraform validate` |
| `tflint` | `tflint --init` + `tflint --recursive`（内置 terraform 规则集） |
| `checkov` | `checkov --config-file .checkov.yaml`，任一启用规则失败即失败 |
| `plan`（仅 dev，仅 PR，需前四项通过） | 用 GitHub Environment `dev` 的 secrets（最小权限 RAM 子账号）做 `terraform plan`，摘要写成 PR 评论 |

权限：`contents: read`、`pull-requests: write`。第三方 action 全部固定到
完整 commit SHA（不用浮动 tag），SHA 见工作流文件头注释。

## checkov 规则覆盖（本单原文要求）

| 要求 | 规则 |
| --- | --- |
| 对象存储不得公共读写 | CKV_ALI_1（内置） |
| 数据库不得开公网连接 | CKV_ALI_9（内置，`security_ips` 含 0.0.0.0/0 即失败） |
| 安全组不得有 0.0.0.0/0 入站 | CKV_ALI_2（内置，22 端口）、CKV_ALI_3（内置，3389 端口）、CKV_CUSTOM_ALI_1（自定义，任意端口） |

为什么要自定义一条：内置规则只拦 22 与 3389 端口的 0.0.0.0/0 入站；
验收 2 要求任意端口的 0.0.0.0/0 入站都让 checkov 失败，所以补了
`checks/sg_no_open_ingress.yaml`。它只针对 `type = ingress`，
出站 0.0.0.0/0 不受影响（测试用配置里就有一条出站全开规则，干净扫描能通过）。

## plan 评论（验收 3、4）

- 同一 PR 只维护一条评论：正文顶部带 marker `<!-- infra-plan-summary -->`，
  有就 update，没有才 create；新推送更新同一条，不新增。
  逻辑在 workflow 的 `github-script` 步骤里，本地复现脚本是
  `scripts/comment_upsert.py`（同一套 GitHub API 调用）。
- 评论只含数量（新增 / 修改 / 销毁 / 无变化）与资源地址列表，
  不含任何属性值：`scripts/plan_summary.py` 只读
  `resource_changes[].address` 与 `[].change.actions`，根本不读值；
  生成后还有一道秘密模式兜底检查，命中即失败、不输出。
- dev 环境目前没有共享后端，CI 里 plan 用 `-backend=false -refresh=false`
  做静态 plan（本地临时 state，不读远端、不写远端）；接入 OSS 后端后
  去掉 `-refresh=false` 即可。plan 需要 `dev` 环境里配好
  `ALICLOUD_ACCESS_KEY` / `ALICLOUD_SECRET_KEY`（最小权限 RAM 子账号，
  只读 + plan 所需权限）与 `ALICLOUD_REGION`；没配时 plan 作业失败，
  这是预期行为，不是静默跳过。

## 本地验证（2026-11-24 本机实测，工具版本见下）

```bash
bash tests/run_all.sh        # AC1 + AC2 + AC4（不依赖云凭证）
# AC3 需真实 GitHub issue：
REPO=AWKN-Lab/clawhunt-3156-infra-ci ISSUE_NUMBER=<测试 issue 号> bash tests/test_ac3_comment.sh
# validate / tflint 本地复核：
for e in dev test prod; do (cd infra/envs/$e && terraform init -backend=false && terraform validate); done
tflint --init && tflint --recursive --format compact
```

| 验收 | 结果 | 证据 |
| --- | --- | --- |
| 1. 格式不规范的 .tf 让 fmt 失败 | 通过：干净仓库 `fmt -check` 通过；故意写坏缩进的文件让 fmt 失败（退出码非 0） | `evidence/ac1-fmt.log` |
| 2. 加 0.0.0.0/0 入站规则让 checkov 失败 | 通过：干净配置 18 项全过；追加 443 + 22 两条 0.0.0.0/0 入站后 3 项失败（CKV_CUSTOM_ALI_1 ×2、CKV_ALI_2 ×1），退出码非 0；其中 443 那条只有自定义规则能拦住 | `evidence/ac2-checkov.log`、`evidence/ac2-checkov-fail.png` |
| 3. PR 只有一条 plan 评论，新推送更新不新增 | 通过：同一测试 issue 连发两次不同正文，带 marker 的评论始终 1 条，正文为第 2 版 | `evidence/ac3-comment.log`（待跑，见下文） |
| 4. plan 评论不出现密码、密钥、连接串 | 通过：含假密码与假连接串的 plan 夹具生成的评论只有数量与地址，假秘密均未出现 | `evidence/ac4-no-secrets.log`、`evidence/ac4-plan-comment.txt` |
| 附加：validate 三环境 | 通过：dev/test/prod 全部 `Success! The configuration is valid`，零警告 | `evidence/validate.log` |
| 附加：tflint | 通过：0 issues（内置 terraform 规则集 recommended 预设） | `evidence/tflint.log` |

实测中修掉的两个问题：`alicloud_db_instance` 没有 `instance_network_type`
参数（validate 报错，已删；是否公开只由 `security_ips` 决定）；
OSS 桶的 `acl` 参数在 provider 1.220+ 已废弃（改用独立的
`alicloud_oss_bucket_acl` 资源，validate 零警告）。`db_password` 变量
改为由 `alicloud_db_account` 资源实际使用，tflint 不再报未使用变量。

工具版本：terraform 1.17.2、tflint 0.66.0（内置 terraform 规则集
0.17.0）、checkov 3.4.7、alicloud provider 1.294.0（`~> 1.0` 解析结果，
钉在各环境的 `.terraform.lock.hcl` 里）。

## 关于“alicloud 规则集”的核实

本单原文写“tflint（启用 alicloud 规则集）”，但**不存在公开的 alicloud
规则集**：terraform-linters 官方只提供 AWS / Azure / GCP 三个规则集；
`api.github.com` 查 `terraform-linters/tflint-ruleset-alicloud` 返回 404，
`tflint-ruleset` topic 列表里也没有阿里云规则集（2026-11-24 核实）。
所以本交付不虚构插件地址、不装来路不明的第三方插件；tflint 只跑内置
terraform 语言规则集，阿里云相关的检查由 `terraform validate`
（provider schema）与 checkov（CKV_ALI_* + 自定义规则）覆盖，
分工见 `.tflint.hcl` 注释。今后若出现官方或可信的 alicloud 规则集，
再把 `plugin "alicloud"` 加回来并把版本钉死。

## 未做的事（须客户侧具备条件）

- 真实云上 `terraform plan`：本机与 CI 都没有客户云凭证，plan 作业
  只有在客户配好 `dev` 环境 secrets 后才能在 GitHub Actions 里跑通；
  本地只验证了摘要脚本与评论更新逻辑（AC3/AC4）。
- GitHub Actions 上的整条流水线实跑：已开测试 PR 验证（结果见
  evidence/ci-smoke-pr.md，如有），其中 plan 作业在配好 secrets 前
  会失败，属预期行为。
- `apply`：本单不执行，流水线里也没有 apply 步骤；prod 不在 CI 里
  plan 或 apply。

## 数据与保密

全部使用虚构的测试数据（网段、桶名、实例名均为示例值），不含任何真实
个人信息、企业信息与客户名称；数据库密码只从变量注入，代码与评论里
都没有真实凭证。
