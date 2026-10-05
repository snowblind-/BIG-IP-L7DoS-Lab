#!/usr/bin/env python
# Minimal lab DNS responder for F5 Bot Defense search-engine (FCrDNS) verification.
# Runs on Python 2.7 AND 3.x (no f-strings; bytearray-normalized parsing).
#   PTR 10.1.10.100 -> crawl-lab-100.googlebot.com   (reverse)
#   A   crawl-lab-100.googlebot.com -> 10.1.10.100   (forward-confirm)
# 10.1.10.200 has no record -> stays a masquerader.
import socket, struct, sys
PTR = {"100.10.1.10.in-addr.arpa": "crawl-lab-100.googlebot.com"}
A   = {"crawl-lab-100.googlebot.com": "10.1.10.100"}
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 53

def parse_qname(data, off):
    labels = []
    while True:
        n = data[off]
        if n == 0:
            off += 1
            break
        labels.append(data[off+1:off+1+n].decode())
        off += 1 + n
    return ".".join(labels), off

def encode_name(name):
    out = b""
    for part in name.split("."):
        out += struct.pack("B", len(part)) + part.encode()
    return out + b"\x00"

def handle(raw):
    data = bytearray(raw)            # byte-indexing returns int on py2 and py3
    tid = bytes(data[:2])
    qd = struct.unpack(">H", bytes(data[4:6]))[0]
    qname, off = parse_qname(data, 12)
    qtype, qclass = struct.unpack(">HH", bytes(data[off:off+4]))
    off += 4
    question = bytes(data[12:off])
    q = qname.lower()
    ans = b""; an = 0; rcode = 3
    if qtype == 12 and q in PTR:
        rd = encode_name(PTR[q])
        ans = b"\xc0\x0c" + struct.pack(">HHIH", 12, 1, 60, len(rd)) + rd
        an = 1; rcode = 0
    elif qtype == 1 and q in A:
        rd = socket.inet_aton(A[q])
        ans = b"\xc0\x0c" + struct.pack(">HHIH", 1, 1, 60, 4) + rd
        an = 1; rcode = 0
    hdr = tid + struct.pack(">HHHHH", 0x8400 | rcode, qd, an, 0, 0)
    return hdr + question + ans, qname, qtype, an

def main():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("0.0.0.0", PORT))
    print("lab DNS responder on :%d  (Ctrl-C to stop)" % PORT); sys.stdout.flush()
    while True:
        raw, addr = s.recvfrom(512)
        try:
            resp, qn, qt, an = handle(raw)
            s.sendto(resp, addr)
            print("q %s type=%d from %s -> %s" % (qn, qt, addr[0], "ANSWER" if an else "NXDOMAIN")); sys.stdout.flush()
        except Exception as e:
            print("err: %s" % e); sys.stdout.flush()

if __name__ == "__main__":
    main()
