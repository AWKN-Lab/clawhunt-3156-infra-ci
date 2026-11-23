#!/usr/bin/env bash
# 验收 4：plan 评论中不出现任何密码、密钥或连接串。
# 做法：用含假密码与假连接串的 plan JSON（tests/fixtures/plan-with-secret.json）
# 跑 scripts/plan_summary.py，断言输出里有数量与资源地址、且不含假秘密。
set -u
cd "$(dirname "$0")/.."
LOG="evidence/ac4-no-secrets.log"
mkdir -p evidence
: > "$LOG"

python3 scripts/plan_summary.py tests/fixtures/plan-with-secret.json > evidence/ac4-plan-comment.txt 2>> "$LOG"
test "${PIPESTATUS[0]}" -eq 0 || { echo "FAIL：plan_summary.py 失败" | tee -a "$LOG"; exit 1; }
echo "== 生成的 plan 评论 ==" | tee -a "$LOG"
cat evidence/ac4-plan-comment.txt | tee -a "$LOG"

echo "" | tee -a "$LOG"
echo "== 断言 1：含数量与资源地址 ==" | tee -a "$LOG"
grep -q "新增 | 3" evidence/ac4-plan-comment.txt || { echo "FAIL：缺新增数量" | tee -a "$LOG"; exit 1; }
grep -q "修改 | 1" evidence/ac4-plan-comment.txt || { echo "FAIL：缺修改数量" | tee -a "$LOG"; exit 1; }
grep -q "alicloud_db_instance.main" evidence/ac4-plan-comment.txt || { echo "FAIL：缺资源地址" | tee -a "$LOG"; exit 1; }
echo "PASS：数量与资源地址齐全" | tee -a "$LOG"

echo "== 断言 2：不含假密码与假连接串 ==" | tee -a "$LOG"
if grep -q "FakeDbPassw0rd" evidence/ac4-plan-comment.txt; then
  echo "FAIL：评论里出现了假密码，验收 4 不成立" | tee -a "$LOG"; exit 1
fi
if grep -q "rm-example.mysql.rds.aliyuncs.com" evidence/ac4-plan-comment.txt; then
  echo "FAIL：评论里出现了假连接串，验收 4 不成立" | tee -a "$LOG"; exit 1
fi
if grep -qiE "password|secret|token|api[_-]?key" evidence/ac4-plan-comment.txt; then
  echo "FAIL：评论里出现秘密类字样，验收 4 不成立" | tee -a "$LOG"; exit 1
fi
echo "PASS：假密码与假连接串均未出现，验收 4 通过" | tee -a "$LOG"
echo "" | tee -a "$LOG"
echo "验收 4 通过。评论样本：evidence/ac4-plan-comment.txt" | tee -a "$LOG"
