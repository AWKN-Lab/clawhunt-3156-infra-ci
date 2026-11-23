#!/usr/bin/env python3
"""把 `terraform show -json tfplan` 的输出转成 PR 评论。

只输出两类信息：数量（新增 / 修改 / 销毁 / 无变化）与资源地址列表。
绝不输出任何属性值、变量值、输出值 —— 脚本只读
resource_changes[].address 与 [].change.actions，根本不碰
change.after / before / after_unknown / configuration。

兜底检查：生成正文后用秘密模式再扫一遍，命中即失败退出、不输出。
用法：python3 plan_summary.py plan.json > plan-summary.md
"""

import json
import re
import sys

MARKER = "<!-- infra-plan-summary -->"

# 兜底：评论正文里绝不该出现的模式（万一上游格式变化导致值被带入）。
SECRET_PATTERNS = [
    re.compile(r"(?i)(password|passwd|secret|token|api[_-]?key|access[_-]?key)"),
    re.compile(r"(?i)(aliyun|aws|acs)://[^\s]*:[^\s]*@"),
    re.compile(r"://[^/\s:]+:[^/\s@]+@"),  # user:pass@host 形式的连接串
    re.compile(r"(?i)connection[_-]?string"),
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
]

ACTION_LABELS = {
    "create": "新增",
    "update": "修改",
    "delete": "销毁",
    "replace": "替换（销毁后重建）",
    "read": "读取（仅读）",
    "no-op": "无变化",
    "forget": "遗忘（仅脱离 state）",
}


def classify(actions):
    """terraform change.actions -> 本评论用的分组。"""
    acts = sorted(actions)
    if acts == ["create"]:
        return "create"
    if acts == ["update"]:
        return "update"
    if acts == ["delete"]:
        return "delete"
    if acts == ["delete", "create"]:
        return "replace"
    if acts == ["read"]:
        return "read"
    if acts == ["no-op"]:
        return "no-op"
    if acts == ["forget"]:
        return "forget"
    return "update"  # 其他组合（如 ["create", "read"]）一律按“修改”计，不展开细节


def main() -> int:
    if len(sys.argv) != 2:
        print("用法：plan_summary.py <terraform show -json 输出>", file=sys.stderr)
        return 2
    with open(sys.argv[1], encoding="utf-8") as f:
        plan = json.load(f)

    groups = {}
    for rc in plan.get("resource_changes", []) or []:
        # 只取地址与动作两个字段；change.after/before 等值一律不读。
        address = rc.get("address", "")
        actions = (rc.get("change") or {}).get("actions") or []
        if not address or not actions:
            continue
        groups.setdefault(classify(actions), []).append(address)

    counts = {k: len(v) for k, v in groups.items()}
    total = sum(counts.values())

    lines = [
        MARKER,
        "## Terraform Plan 摘要（dev 环境）",
        "",
        "本评论只含数量与资源地址，**不含任何属性值、密码、密钥或连接串**。",
        "",
        "| 动作 | 数量 |",
        "| --- | ---: |",
    ]
    for key in ("create", "update", "delete", "replace", "read", "no-op", "forget"):
        if counts.get(key):
            lines.append(f"| {ACTION_LABELS[key]} | {counts[key]} |")
    lines += ["", f"合计资源：{total} 个", ""]
    for key in ("create", "update", "delete", "replace", "read", "no-op", "forget"):
        addrs = sorted(groups.get(key, []))
        if not addrs:
            continue
        lines.append(f"### {ACTION_LABELS[key]}（{len(addrs)}）")
        lines.append("")
        for addr in addrs:
            lines.append(f"- `{addr}`")
        lines.append("")

    body = "\n".join(lines).rstrip() + "\n"

    for pattern in SECRET_PATTERNS:
        if pattern.search(body):
            print(f"拒绝输出：plan 摘要命中秘密模式 {pattern.pattern!r}", file=sys.stderr)
            return 1
    sys.stdout.write(body)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
