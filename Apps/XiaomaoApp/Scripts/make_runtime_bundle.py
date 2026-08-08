#!/usr/bin/env python3
"""Create an Xiaomao XM1 runtime configuration bundle.

The token is read from a file so it does not need to appear in shell history.
When --output is used the bundle is written with owner-only permissions and is
not printed to stdout.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
from pathlib import Path
from urllib.parse import urlparse


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description="Create an XM1 runtime configuration bundle")
    result.add_argument("--backend", required=True, help="Backend HTTPS URL")
    result.add_argument("--voice", required=True, help="Voice WSS URL")
    result.add_argument("--device-id", required=True, help="Bound device ID")
    result.add_argument("--token-file", required=True, type=Path, help="File containing the access token")
    result.add_argument("--output", type=Path, help="Write bundle to an owner-only file instead of stdout")
    return result


def validate_url(value: str, scheme: str) -> str:
    normalized = value.strip()
    parsed = urlparse(normalized)
    if parsed.scheme.lower() != scheme or not parsed.netloc:
        raise ValueError(f"expected {scheme} URL")
    return normalized


def build_bundle(backend: str, voice: str, device_id: str, token: str) -> str:
    backend = validate_url(backend, "https")
    voice = validate_url(voice, "wss")
    device_id = device_id.strip()
    token = token.strip()
    if token.lower().startswith("bearer "):
        token = token[7:].strip()
    if not device_id or not token:
        raise ValueError("device ID and token must be non-empty")
    payload = json.dumps(
        {
            "backend": backend,
            "voice": voice,
            "device": device_id,
            "token": token,
        },
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode("utf-8")
    encoded = base64.urlsafe_b64encode(payload).decode("ascii").rstrip("=")
    return "XM1." + encoded


def write_private(path: Path, value: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        os.write(fd, (value + "\n").encode("utf-8"))
    finally:
        os.close(fd)
    os.chmod(path, 0o600)


def main() -> int:
    args = parser().parse_args()
    token = args.token_file.read_text(encoding="utf-8")
    bundle = build_bundle(args.backend, args.voice, args.device_id, token)
    if args.output:
        write_private(args.output, bundle)
        print(f"bundle written: {args.output} (mode 0600)")
    else:
        print(bundle)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
