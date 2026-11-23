#!/usr/bin/env python3
"""Benchmark the resumable transfer kernel with the current device login."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import plistlib
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import requests
import urllib3


urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


def elapsed_ms(started: float) -> int:
    return round((time.monotonic() - started) * 1000)


def payload(seed: int, size: int) -> bytes:
    stream = hashlib.shake_256(str(seed).encode()).digest(size)
    return stream


def test_one(session: requests.Session,
             base: str,
             token: str,
             chunk_size: int,
             size_mb: int,
             workers: int) -> dict[str, object]:
    size = size_mb * 1024 * 1024
    started = time.monotonic()
    data = payload(size_mb, size)
    hash_ms = elapsed_ms(started)

    sha256 = hashlib.sha256(data).hexdigest()
    headers = {
        "Authorization": f"Bearer {token}",
        "User-Agent": "Xingyan-Transfer-Benchmark/1",
    }

    started = time.monotonic()
    response = session.post(
        base + "/api/transfer/init",
        headers={**headers, "Content-Type": "application/json"},
        json={
            "size": size,
            "sha256": sha256,
            "name": f"xingyan-bench-{size_mb}mb-{uuid.uuid4().hex}.bin",
            "mime": "application/octet-stream",
            "skipTranscode": True,
        },
        timeout=30,
        verify=False,
    )
    init_ms = elapsed_ms(started)
    response.raise_for_status()
    transfer = response.json()["data"]["transfer"]
    transfer_id = transfer["id"]
    chunk_size = int(transfer["chunkSize"])
    total_chunks = int(transfer["totalChunks"])
    missing = list(transfer["missing"])

    chunk_started: dict[int, float] = {}
    chunk_ms: dict[int, int] = {}
    lock = threading.Lock()

    def put(index: int) -> tuple[int, int]:
        offset = index * chunk_size
        chunk = data[offset:min(size, offset + chunk_size)]
        digest = hashlib.sha256(chunk).hexdigest()
        with lock:
            chunk_started[index] = time.monotonic()
        result = requests.post(
            f"{base}/api/transfer/{transfer_id}/chunk",
            headers={
                **headers,
                "Content-Type": "application/octet-stream",
                "x-transfer-chunk-index": str(index),
                "x-transfer-chunk-sha256": digest,
            },
            data=chunk,
            timeout=120,
            verify=False,
        )
        result.raise_for_status()
        duration = elapsed_ms(chunk_started[index])
        with lock:
            chunk_ms[index] = duration
        return index, duration

    upload_started = time.monotonic()
    active_workers = min(workers, len(missing))
    with ThreadPoolExecutor(max_workers=active_workers) as pool:
        futures = [pool.submit(put, index) for index in missing]
        for future in as_completed(futures):
            future.result()
    upload_ms = elapsed_ms(upload_started)

    started = time.monotonic()
    response = session.post(
        f"{base}/api/transfer/{transfer_id}/complete",
        headers=headers,
        timeout=120,
        verify=False,
    )
    complete_ms = elapsed_ms(started)
    response.raise_for_status()
    completed = response.json()["data"]["transfer"]
    if completed["status"] != "ready":
        raise RuntimeError(f"transfer {transfer_id} ended as {completed['status']}")

    total_ms = hash_ms + init_ms + upload_ms + complete_ms
    return {
        "size_mb": size_mb,
        "chunk_size_mb": round(chunk_size / 1024 / 1024, 2),
        "total_chunks": total_chunks,
        "concurrency": active_workers,
        "hash_ms": hash_ms,
        "init_ms": init_ms,
        "upload_ms": upload_ms,
        "complete_ms": complete_ms,
        "total_ms": total_ms,
        "upload_mbps": round(size_mb / (upload_ms / 1000), 2) if upload_ms else None,
        "overall_mbps": round(size_mb / (total_ms / 1000), 2) if total_ms else None,
        "first_chunk_ms": min(chunk_ms.values()) if chunk_ms else None,
        "slowest_chunk_ms": max(chunk_ms.values()) if chunk_ms else None,
        "url_ok": bool(completed["url"].startswith("/uploads/")),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--prefs",
        default=str(
            Path(__file__).resolve().parents[1]
            / "diagnostics"
            / "chris-prefs.plist"
        ),
    )
    parser.add_argument("--sizes", default="5,20,60")
    parser.add_argument("--base", default="")
    parser.add_argument("--workers", type=int, default=3)
    args = parser.parse_args()

    with Path(args.prefs).open("rb") as file:
        prefs = plistlib.load(file)
    token = str(prefs.get("chris.token") or "")
    server = str(prefs.get("chris.server") or "").strip()
    if not token or not server:
        raise SystemExit("missing login token or server")
    base = server if server.startswith(("http://", "https://")) else "https://" + server
    if server == "mail.xingyanmail.site:443":
        base += "/xy"
    base = base.rstrip("/")
    if args.base:
        base = args.base.rstrip("/")

    session = requests.Session()
    session.trust_env = False
    session.verify = False
    headers = {
        "Authorization": f"Bearer {token}",
        "User-Agent": "Xingyan-Transfer-Benchmark/1",
    }
    started = time.monotonic()
    capability = session.get(
        base + "/api/transfer/capabilities",
        headers=headers,
        timeout=10,
        verify=False,
    )
    probe_ms = elapsed_ms(started)
    capability.raise_for_status()
    cap = capability.json()["data"]
    if not cap.get("chunked") or not cap.get("resumable"):
        raise SystemExit("transfer kernel is not available")

    results = []
    for size_mb in [int(value) for value in args.sizes.split(",")]:
        result = test_one(
            session,
            base,
            token,
            int(cap["maxChunkBytes"]),
            size_mb,
            max(1, args.workers),
        )
        results.append(result)
        print(json.dumps(result, ensure_ascii=False))

    print(json.dumps({
        "base": base,
        "capability_probe_ms": probe_ms,
        "capabilities": cap,
        "results": results,
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
