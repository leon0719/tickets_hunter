#!/usr/bin/env bash
# 同步 upstream/main 到本機 main，並推回 origin (個人 fork)。
# 用法：./sync-upstream.sh
#
# 前置需求：
#   - 已設定 remote `upstream`（指向原作者 repo）
#   - 已設定 remote `origin` （指向你的 fork）
#   - `main` 分支永遠不放自己的 commit（保持為 upstream 鏡像）

set -euo pipefail

UPSTREAM_REMOTE="${UPSTREAM_REMOTE:-upstream}"
ORIGIN_REMOTE="${ORIGIN_REMOTE:-origin}"
MAIN_BRANCH="${MAIN_BRANCH:-main}"

# 檢查兩個 remote 都存在
if ! git remote get-url "$UPSTREAM_REMOTE" >/dev/null 2>&1; then
    echo "[ERROR] 找不到 remote '$UPSTREAM_REMOTE'。請先執行："
    echo "    git remote add $UPSTREAM_REMOTE <upstream URL>"
    exit 1
fi
if ! git remote get-url "$ORIGIN_REMOTE" >/dev/null 2>&1; then
    echo "[ERROR] 找不到 remote '$ORIGIN_REMOTE'。"
    exit 1
fi

# 檢查工作目錄是否乾淨（rebase.autoStash 不一定全域開啟，保險起見）
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    echo "[ERROR] 工作目錄有未 commit 的修改，請先 commit 或 stash。"
    exit 1
fi

CURRENT_BRANCH="$(git symbolic-ref --short HEAD)"

echo "[1/4] 切換到 $MAIN_BRANCH"
git checkout "$MAIN_BRANCH"

echo "[2/4] 抓取 $UPSTREAM_REMOTE"
git fetch "$UPSTREAM_REMOTE"

echo "[3/4] 快轉合併 $UPSTREAM_REMOTE/$MAIN_BRANCH (--ff-only)"
if ! git merge --ff-only "$UPSTREAM_REMOTE/$MAIN_BRANCH"; then
    echo ""
    echo "[ERROR] 無法快轉。$MAIN_BRANCH 上可能有自己的 commit。"
    echo "        檢查：git log $UPSTREAM_REMOTE/$MAIN_BRANCH..$MAIN_BRANCH"
    git checkout "$CURRENT_BRANCH"
    exit 1
fi

echo "[4/4] 推到 $ORIGIN_REMOTE/$MAIN_BRANCH"
git push "$ORIGIN_REMOTE" "$MAIN_BRANCH"

# 回到原本分支
if [ "$CURRENT_BRANCH" != "$MAIN_BRANCH" ]; then
    echo ""
    echo "切回 $CURRENT_BRANCH"
    git checkout "$CURRENT_BRANCH"
    echo ""
    echo "下一步若要把上游進度套用到 $CURRENT_BRANCH："
    echo "    git rebase $MAIN_BRANCH"
    echo "    git push --force-with-lease $ORIGIN_REMOTE $CURRENT_BRANCH"
fi

echo ""
echo "[DONE] upstream/$MAIN_BRANCH 已同步到 $ORIGIN_REMOTE/$MAIN_BRANCH"
