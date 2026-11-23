#!/usr/bin/env python3
"""按 marker 更新或新建一条 issue/PR 评论（AC3 本地验证用）。

与 .github/workflows/infra-ci.yml 里 github-script 步骤完全相同的语义：
按 marker 找已有的评论，找到就 update，找不到才 create；同一 PR
永远只有一条带该 marker 的评论。

依赖 gh CLI（已登录 AWKN-Lab）。用法：
  python3 comment_upsert.py --repo OWNER/REPO --number N \
      --body-file plan-summary.md --marker '<!-- infra-plan-summary -->'
"""

import argparse
import json
import subprocess
import sys


def gh(*args):
    out = subprocess.run(
        ["gh", "api", *args], capture_output=True, text=True, check=True
    )
    return json.loads(out.stdout) if out.stdout.strip() else {}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("--number", required=True, type=int)
    ap.add_argument("--body-file", required=True)
    ap.add_argument("--marker", required=True)
    args = ap.parse_args()

    with open(args.body_file, encoding="utf-8") as f:
        body = f.read()
    if args.marker not in body:
        print("body 文件里没有 marker，拒绝发送", file=sys.stderr)
        return 2

    comments = gh(
        f"repos/{args.repo}/issues/{args.number}/comments",
        "--paginate",
    )
    existing = [c for c in comments if args.marker in (c.get("body") or "")]
    if len(existing) > 1:
        print(f"异常：找到 {len(existing)} 条带 marker 的评论（应为 0 或 1）", file=sys.stderr)
        return 1

    if existing:
        comment_id = existing[0]["id"]
        gh(
            f"repos/{args.repo}/issues/comments/{comment_id}",
            "-X", "PATCH",
            "-f", f"body={body}",
        )
        print(f"updated comment {comment_id} on #{args.number}")
    else:
        created = gh(
            f"repos/{args.repo}/issues/{args.number}/comments",
            "-f", f"body={body}",
        )
        print(f"created comment {created['id']} on #{args.number}")

    after = gh(f"repos/{args.repo}/issues/{args.number}/comments", "--paginate")
    marked = [c for c in after if args.marker in (c.get("body") or "")]
    print(f"带 marker 的评论数：{len(marked)}（应为 1）")
    return 0 if len(marked) == 1 else 1


if __name__ == "__main__":
    raise SystemExit(main())
