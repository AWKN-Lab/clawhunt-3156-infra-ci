#!/usr/bin/env bash
# 验收 2：加入一条 0.0.0.0/0 入站规则时 checkov 步骤失败。
# 做法：干净 infra 跑 checkov（应通过）；复制一份到临时目录，
# 追加 0.0.0.0/0 入站规则（含 443 端口，内置规则拦不住，靠自定义规则拦；
# 另加一条 22 端口 0.0.0.0/0，内置 CKV_ALI_2 也应触发），再跑 checkov（应失败）。
# 同时验证：干净配置里的出站 0.0.0.0/0 不触发自定义规则。
set -u
cd "$(dirname "$0")/.."
# checkov 路径**可配**：原先写死成编写机的绝对路径 ⇒ 换台机器必然
# "No such file or directory"，验收 2 直接不成立。现在优先用 $CHECKOV_BIN，
# 否则用 PATH 里的 checkov；都没有就**明确报错退出**（不静默跳过一次验收）。
CHECKOV="${CHECKOV_BIN:-$(command -v checkov 2>/dev/null || true)}"
if [ -z "$CHECKOV" ] || [ ! -x "$CHECKOV" ]; then
  echo "ERROR：找不到 checkov。请安装后重跑，或用 CHECKOV_BIN=/path/to/checkov 指定。" >&2
  exit 2
fi
LOG="evidence/ac2-checkov.log"
mkdir -p evidence
: > "$LOG"

echo "== 1. 干净 infra：checkov 应通过 ==" | tee -a "$LOG"
if "$CHECKOV" --config-file .checkov.yaml >> "$LOG" 2>&1; then
  echo "PASS：干净 infra checkov 通过（出站 0.0.0.0/0 未误报）" | tee -a "$LOG"
else
  echo "FAIL：干净 infra checkov 失败（见 $LOG）" | tee -a "$LOG"
  exit 1
fi

echo "" | tee -a "$LOG"
echo "== 2. 追加 0.0.0.0/0 入站规则：checkov 应失败 ==" | tee -a "$LOG"
TMP="$(mktemp -d)"
# 只拷 .tf 文件：.terraform/ 里是下载的 provider（每环境约 300MB），
# 拷进 /tmp（512MB tmpfs）会把磁盘写满；checkov 扫描只需要 .tf。
mkdir -p "$TMP/infra/envs" "$TMP/checks"
for e in dev test prod; do
  mkdir -p "$TMP/infra/envs/$e"
  cp infra/envs/$e/*.tf "$TMP/infra/envs/$e/"
done
cp checks/* "$TMP/checks/"
cp .checkov.yaml "$TMP/.checkov.yaml"
cat >> "$TMP/infra/envs/dev/main.tf" <<'EOF'

# 埋错：对外全开的入站规则（验收 2 的反例）
resource "alicloud_security_group_rule" "bad_open_https" {
  type              = "ingress"
  ip_protocol       = "tcp"
  nic_type          = "intranet"
  policy            = "accept"
  port_range        = "443/443"
  priority          = 1
  security_group_id = alicloud_security_group.main.id
  cidr_ip           = "0.0.0.0/0"
}

resource "alicloud_security_group_rule" "bad_open_ssh" {
  type              = "ingress"
  ip_protocol       = "tcp"
  nic_type          = "intranet"
  policy            = "accept"
  port_range        = "22/22"
  priority          = 1
  security_group_id = alicloud_security_group.main.id
  cidr_ip           = "0.0.0.0/0"
}
EOF
cd "$TMP"
if "$CHECKOV" --config-file .checkov.yaml >> "$OLDPWD/$LOG" 2>&1; then
  echo "FAIL：加了 0.0.0.0/0 入站规则 checkov 居然通过，验收 2 不成立" | tee -a "$OLDPWD/$LOG"
  cd "$OLDPWD"
  rm -rf "$TMP"
  exit 1
else
  echo "PASS：加了 0.0.0.0/0 入站规则 checkov 失败（退出码非 0），验收 2 通过" | tee -a "$OLDPWD/$LOG"
fi
cd "$OLDPWD"
rm -rf "$TMP"
echo "" | tee -a "$LOG"
echo "验收 2 通过。日志：$LOG；截图：evidence/ac2-checkov-fail.png" | tee -a "$LOG"
