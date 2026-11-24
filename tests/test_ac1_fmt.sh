#!/usr/bin/env bash
# 验收 1：格式不规范的 .tf 文件会让 fmt 步骤失败。
# 做法：先在干净仓库上跑 terraform fmt -check（应通过），再把故意写坏
# 格式的 .tf 复制进临时目录跑同样的命令（应失败、退出码非 0）。
set -u
cd "$(dirname "$0")/.."
# terraform 路径可配：原先把编写机的 tools/bin 硬塞进 PATH（目录在别的机器上
# 不存在，等于没设）。现在优先用 $TF_BIN，否则用 PATH 里的 terraform；
# 都没有就**明确报错退出**（不静默跳过一次验收）。
if [ -n "${TF_BIN:-}" ]; then
  export PATH="$(dirname "$TF_BIN"):$PATH"
fi
TF="${TF_BIN:-$(command -v terraform 2>/dev/null || true)}"
if [ -z "$TF" ] || [ ! -x "$TF" ]; then
  echo "ERROR：找不到 terraform。请安装后重跑，或用 TF_BIN=/path/to/terraform 指定。" >&2
  exit 2
fi
LOG="evidence/ac1-fmt.log"
mkdir -p evidence
: > "$LOG"

echo "== 1. 干净仓库：terraform fmt -check -recursive 应通过 ==" | tee -a "$LOG"
if terraform fmt -check -recursive -diff >> "$LOG" 2>&1; then
  echo "PASS：干净仓库 fmt 通过" | tee -a "$LOG"
else
  echo "FAIL：干净仓库 fmt 居然失败（见 $LOG）" | tee -a "$LOG"
  exit 1
fi

echo "" | tee -a "$LOG"
echo "== 2. 故意写坏格式的 .tf：fmt 步骤应失败 ==" | tee -a "$LOG"
TMP="$(mktemp -d)"
cp infra/envs/dev/main.tf "$TMP/bad.tf"
# 故意破坏缩进与对齐（模拟没跑过 fmt 就提交的文件）
python3 - "$TMP/bad.tf" <<'EOF'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace('  vpc_name   = "member-space', 'vpc_name="member-space')
s = s.replace('  cidr_block = var.vpc_cidr', 'cidr_block=var.vpc_cidr')
open(p, "w").write(s)
EOF
if terraform fmt -check -recursive -diff "$TMP" >> "$LOG" 2>&1; then
  echo "FAIL：写坏格式的文件 fmt 居然通过，验收 1 不成立" | tee -a "$LOG"
  rm -rf "$TMP"
  exit 1
else
  echo "PASS：写坏格式的文件让 fmt 失败（退出码非 0），验收 1 通过" | tee -a "$LOG"
fi
rm -rf "$TMP"
echo "" | tee -a "$LOG"
echo "验收 1 通过。日志：$LOG" | tee -a "$LOG"
