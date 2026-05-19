#!/usr/bin/env python3
"""
Patch mihomo adapter/outbound/tailscale.go for the current metacubex/tailscale API.
This script is intended to run inside GitHub Actions after the mihomo submodule has
been checked out, so the parent repository does not need to vendor or fork mihomo.
"""
from __future__ import annotations

import re
from pathlib import Path

TARGET = Path("core/src/foss/golang/clash/adapter/outbound/tailscale.go")


def main() -> None:
    if not TARGET.exists():
        raise SystemExit(f"target file not found: {TARGET}")

    text = TARGET.read_text(encoding="utf-8")
    original = text

    text = text.replace('\n\t"github.com/metacubex/mihomo/component/dialer"', "")
    text = text.replace('\r\n\t"github.com/metacubex/mihomo/component/dialer"', "")

    text = text.replace(
        "SystemPacketListener: tailscalePacketListener{dialer: outbound.dialer}.ListenPacket,",
        "SystemPacketListener: tailscalePacketListener{dialer: outbound.dialer},",
    )

    replacement = '''func (t *Tailscale) DialContext(ctx context.Context, metadata *C.Metadata) (_ C.Conn, err error) {
\tif err = t.ensureStarted(ctx); err != nil {
\t\treturn nil, err
\t}
\tvar conn net.Conn
\tconn, err = t.server.Dial(ctx, "tcp", metadata.RemoteAddress())
\tif err != nil {
\t\treturn nil, err
\t}
\tif conn == nil {
\t\treturn nil, errors.New("conn is nil")
\t}
\treturn NewConn(conn, t), nil
}

func (t *Tailscale) ListenPacketContext'''

    pattern = re.compile(
        r"func \(t \*Tailscale\) DialContext\(ctx context\.Context, metadata \*C\.Metadata\) "
        r"\(_ C\.Conn, err error\) \{.*?\n\}\s*\nfunc \(t \*Tailscale\) ListenPacketContext",
        re.S,
    )
    text, count = pattern.subn(replacement, text, count=1)
    if count != 1:
        raise SystemExit("failed to replace Tailscale.DialContext block")

    forbidden = [
        "t.server.Netstack(ctx)",
        "dialer.NewDialer",
        "tailscalePacketListener{dialer: outbound.dialer}.ListenPacket",
        '"github.com/metacubex/mihomo/component/dialer"',
    ]
    remaining = [item for item in forbidden if item in text]
    if remaining:
        raise SystemExit("patch incomplete; remaining markers: " + ", ".join(remaining))

    if text != original:
        TARGET.write_text(text, encoding="utf-8")
        print(f"patched {TARGET}")
    else:
        print(f"no changes needed for {TARGET}")


if __name__ == "__main__":
    main()