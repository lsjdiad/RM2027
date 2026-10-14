#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""WSL Ubuntu 命令助手：python wsl_run.py "bash 命令"
绕开 PowerShell 嵌套转义地狱。输出 UTF-8。
"""
import subprocess, sys

sys.stdout.reconfigure(encoding='utf-8')

def run(cmd, timeout=600):
    r = subprocess.run(['wsl.exe', '-d', 'Ubuntu-24.04', '--', 'bash', '-c', cmd],
                       capture_output=True, timeout=timeout)
    out = r.stdout.decode('utf-8', errors='replace')
    err = r.stderr.decode('utf-8', errors='replace')
    # 过滤 wsl localhost 代理提示的 UTF-16 乱码行
    err = '\n'.join(l for l in err.splitlines() if 'wsl' not in l.lower() or 'bash' in l.lower())
    return out + (('\n[stderr]\n' + err) if err.strip() else '')

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('usage: wsl_run.py "bash command" [timeout]')
        sys.exit(1)
    cmd = sys.argv[1]
    tmo = int(sys.argv[2]) if len(sys.argv) > 2 else 600
    print(run(cmd, tmo))
