#!/usr/bin/env bash
# 验收 3：PR 中只有一条 plan 摘要评论，新推送后被更新而不是新增。
# 做法：对测试 issue（REPO / ISSUE_NUMBER 环境变量传入）用
# scripts/comment_upsert.py 连发两次不同正文（模拟两次推送），
# 断言带 marker 的评论始终只有 1 条，且第二次正文覆盖了第一次。
# 该脚本与 workflow 里 github-script 步骤是同一套 API 语义
#（listComments -> 有则 update、无则 create）。
set -u
cd "$(dirname "$0")/.."
: "${REPO:?须传入 REPO=OWNER/REPO}"
: "${ISSUE_NUMBER:?须传入 ISSUE_NUMBER=测试 issue 号}"
LOG="evidence/ac3-comment.log"
mkdir -p evidence
: > "$LOG"
MARKER='<!-- infra-plan-summary -->'

BODY1="$(mktemp)"; BODY2="$(mktemp)"
printf '%s\n## Terraform Plan 摘要（dev 环境）\n\n| 动作 | 数量 |\n| --- | ---: |\n| 新增 | 3 |\n\n- `alicloud_vpc.main`\n' "$MARKER" > "$BODY1"
printf '%s\n## Terraform Plan 摘要（dev 环境）\n\n| 动作 | 数量 |\n| --- | ---: |\n| 新增 | 2 |\n| 修改 | 1 |\n\n- `alicloud_vpc.main`\n- `alicloud_security_group_rule.https_internal`\n' "$MARKER" > "$BODY2"

echo "== 第 1 次发送（模拟第 1 次推送） ==" | tee -a "$LOG"
python3 scripts/comment_upsert.py --repo "$REPO" --number "$ISSUE_NUMBER" \
  --body-file "$BODY1" --marker "$MARKER" 2>&1 | tee -a "$LOG"
test "${PIPESTATUS[0]}" -eq 0 || { echo "FAIL：第 1 次 upsert 失败" | tee -a "$LOG"; exit 1; }

echo "" | tee -a "$LOG"
echo "== 第 2 次发送（模拟新推送，应更新同一条评论） ==" | tee -a "$LOG"
python3 scripts/comment_upsert.py --repo "$REPO" --number "$ISSUE_NUMBER" \
  --body-file "$BODY2" --marker "$MARKER" 2>&1 | tee -a "$LOG"
test "${PIPESTATUS[0]}" -eq 0 || { echo "FAIL：第 2 次 upsert 失败" | tee -a "$LOG"; exit 1; }

echo "" | tee -a "$LOG"
echo "== 断言：带 marker 的评论只有 1 条，且正文是第 2 版 ==" | tee -a "$LOG"
COUNT=$(gh api "repos/$REPO/issues/$ISSUE_NUMBER/comments" --paginate --jq '[.[] | select(.body | contains("'"$MARKER"'"))] | length')
echo "带 marker 的评论数：$COUNT（应为 1）" | tee -a "$LOG"
test "$COUNT" = "1" || { echo "FAIL：评论数不是 1，验收 3 不成立" | tee -a "$LOG"; exit 1; }
gh api "repos/$REPO/issues/$ISSUE_NUMBER/comments" --paginate \
  --jq '.[] | select(.body | contains("'"$MARKER"'")) | .body' | grep -q "修改 | 1" \
  || { echo "FAIL：评论正文不是第 2 版，更新未生效" | tee -a "$LOG"; exit 1; }
echo "PASS：两次发送后仍只有 1 条评论，且正文已更新为第 2 版，验收 3 通过" | tee -a "$LOG"
rm -f "$BODY1" "$BODY2"
