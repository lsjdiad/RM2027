#!/usr/bin/env bash
# mon-hxy.sh —— 隔 N 秒抓一次 console，统计 hxy42688p 的错误行（验证器件在持续出数）
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
N="${1:-4}"
S="${2:-25}"
for i in $(seq 1 "$N"); do
	echo "--- round $i  $(date +%H:%M:%S) ---"
	"$HERE/dumplog.sh" 2>/dev/null > /tmp/mon_raw.txt
	echo "  hxy42688p 相关行数: $(grep -c 'hxy42688p' /tmp/mon_raw.txt || true)"
	echo "  回读失败行数:      $(grep -c 'read back' /tmp/mon_raw.txt || true)"
	echo "  stale/no-new 行数: $(grep -cE 'stale sample|no new sample' /tmp/mon_raw.txt || true)"
	grep -E 'hxy42688p|read back|stale sample|no new sample' /tmp/mon_raw.txt | tail -5
	sleep "$S"
done
