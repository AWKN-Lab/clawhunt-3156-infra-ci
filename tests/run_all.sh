#!/usr/bin/env bash
# 本地验收总入口：AC1（fmt）+ AC2（checkov）+ AC4（plan 评论无秘密）
# 全部不依赖云凭证。AC3 需真实 GitHub issue，单独跑：
#   REPO=AWKN-Lab/clawhunt-3156-infra-ci ISSUE_NUMBER=<号> bash tests/test_ac3_comment.sh
# terraform validate 与 tflint 在 CI 矩阵里跑，本地复核命令见 README。
set -u
cd "$(dirname "$0")/.."
bash tests/test_ac1_fmt.sh || exit 1
bash tests/test_ac2_checkov.sh || exit 1
bash tests/test_ac4_no_secrets.sh || exit 1
echo ""
echo "AC1 / AC2 / AC4 全部通过。"
