#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Local Docker Build Monitor Script with Swap Auto-Cleanup Guard
Monitors local Docker build task and notifies agent immediately upon completion or failure.
Safely cleans Swap & PageCache when Swap usage exceeds 99% without interrupting compilation.
"""

import os
import sys
import time
import subprocess

def check_and_clean_swap():
    try:
        meminfo = {}
        with open('/proc/meminfo', 'r') as f:
            for line in f:
                if ':' in line:
                    parts = line.split(':')
                    key = parts[0].strip()
                    val = parts[1].strip().split()[0]
                    meminfo[key] = int(val)
        
        swap_total = meminfo.get('SwapTotal', 0)
        swap_free = meminfo.get('SwapFree', 0)
        swap_used = swap_total - swap_free
        
        if swap_total > 0:
            swap_percent = (swap_used / swap_total) * 100.0
            if swap_percent >= 90.0:
                print(f"\n[SWAP GUARD] Swap usage reached {swap_percent:.1f}%! Cleaning swap safely...")
                sys.stdout.flush()
                # 1. Sync file buffers & drop page caches to free RAM
                subprocess.run(["sudo", "sync"], check=False)
                subprocess.run(["sudo", "sysctl", "-w", "vm.drop_caches=3"], check=False)
                
                # 2. Check if available memory is sufficient to hold swapped data before running swapoff
                mem_avail = meminfo.get('MemAvailable', 0)
                if mem_avail > swap_used:
                    subprocess.run(["sudo", "swapoff", "-a"], check=False)
                    subprocess.run(["sudo", "swapon", "-a"], check=False)
                    print("[SWAP GUARD] Swap successfully recycled (swapoff -a && swapon -a completed).")
                else:
                    print("[SWAP GUARD] Dropped caches. RAM available is tight, skipped swapoff to prevent OOM.")
                sys.stdout.flush()
    except Exception as e:
        print(f"[SWAP GUARD WARNING] Failed to check/clean swap: {e}")
        sys.stdout.flush()

def monitor_local_build(interval=15):
    print("=== STARTING LOCAL DOCKER BUILD MONITOR (WITH SWAP GUARD) ===")
    sys.stdout.flush()

    while True:
        try:
            # 1. Check and safely manage swap usage if > 99%
            check_and_clean_swap()

            # 2. Check if docker run or run_local_docker_build.sh is running
            res = subprocess.run(["pgrep", "-f", "run_local_docker_build.sh"], capture_output=True, text=True)
            if not res.stdout.strip():
                print("LOCAL_BUILD_FINISHED: Process run_local_docker_build.sh has ended.")
                sys.stdout.flush()
                return
            else:
                print("Monitoring local Docker build... Still running...")
                sys.stdout.flush()
        except Exception as e:
            print(f"Warning during local build monitor: {e}")
            sys.stdout.flush()
        time.sleep(interval)

if __name__ == '__main__':
    monitor_local_build(interval=15)
