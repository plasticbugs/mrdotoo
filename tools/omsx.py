#!/usr/bin/env python3
"""Send Tcl commands to a running openMSX through its control socket.

usage: tools/omsx.py [--pid PID] 'tcl command' ...
Without --pid it picks the only socket in $TMPDIR/openmsx-$USER/.
"""
import glob, html, os, re, socket, sys

args = sys.argv[1:]
pid = None
if args[:1] == ["--pid"]:
    pid, args = args[1], args[2:]
d = os.path.join(os.environ.get("TMPDIR", "/tmp"), f"openmsx-{os.environ['USER']}")
socks = glob.glob(os.path.join(d, f"socket.{pid or '*'}"))
if len(socks) != 1:
    sys.exit(f"sockets: {socks}")
s = socket.socket(socket.AF_UNIX)
s.connect(socks[0])
buf = b""
def until(pat):
    global buf
    while not re.search(pat, buf, re.S):
        buf += s.recv(65536)
s.sendall(b"<openmsx-control>\n")
until(rb"<openmsx-output>")
for cmd in args:
    buf = b""
    s.sendall(f"<command>{html.escape(cmd)}</command>\n".encode())
    until(rb"<reply result=\"(ok|nok)\">.*?</reply>")
    m = re.search(rb"<reply result=\"(ok|nok)\">(.*?)</reply>", buf, re.S)
    out = html.unescape(m.group(2).decode())
    print(out if m.group(1) == b"ok" else "ERROR: " + out)
