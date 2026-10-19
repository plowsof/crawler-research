"""Minimal Monero levin/p2p client: handshake (to get a peer list) and ping (reachability)."""
import os, socket, struct, ipaddress

SIG = 0x0101010101012101
HDR = struct.Struct('<QQ?IiII')
NETWORK_ID = bytes([0x12, 0x30, 0xF1, 0x71, 0x61, 0x04, 0x41, 0x61, 0x17, 0x31, 0x00, 0x82, 0x16, 0xA1, 0xA1, 0x10])
GENESIS = bytes.fromhex('418015bb9ae982a1975da7d79277c2705727a56894ba0fb246adaabb1f4632e3')
CMD_HANDSHAKE, CMD_TIMEDSYNC, CMD_PING = 1001, 1002, 1003

# ---- portable storage ----
T_I64, T_I32, T_I16, T_I8, T_U64, T_U32, T_U16, T_U8, T_DBL, T_STR, T_BOOL, T_OBJ, T_ARR = range(1, 14)
FMT = {T_I64: '<q', T_I32: '<i', T_I16: '<h', T_I8: '<b', T_U64: '<Q', T_U32: '<I', T_U16: '<H', T_U8: '<B', T_DBL: '<d'}

def enc_varint(n):
    if n < 1 << 6: return struct.pack('<B', n << 2)
    if n < 1 << 14: return struct.pack('<H', n << 2 | 1)
    if n < 1 << 30: return struct.pack('<I', n << 2 | 2)
    return struct.pack('<Q', n << 2 | 3)

class Typed:
    def __init__(self, t, v): self.t, self.v = t, v

def enc_val(v):
    if isinstance(v, Typed):
        if v.t == T_STR: return bytes([T_STR]) + enc_varint(len(v.v)) + v.v
        return bytes([v.t]) + struct.pack(FMT[v.t], v.v)
    if isinstance(v, dict): return bytes([T_OBJ]) + enc_obj(v)
    if isinstance(v, list):   # array of objects
        return bytes([T_OBJ | 0x80]) + enc_varint(len(v)) + b''.join(enc_obj(x) for x in v)
    if isinstance(v, bytes): return bytes([T_STR]) + enc_varint(len(v)) + v
    raise TypeError(v)

def enc_obj(d):
    out = enc_varint(len(d))
    for k, v in d.items():
        out += bytes([len(k)]) + k.encode() + enc_val(v)
    return out

def encode(d):
    return struct.pack('<IIB', 0x01011101, 0x01020101, 1) + enc_obj(d)

class Reader:
    def __init__(self, b): self.b, self.p = b, 0
    def take(self, n):
        if self.p + n > len(self.b): raise ValueError('short')
        r = self.b[self.p:self.p + n]; self.p += n; return r
    def varint(self):
        m = self.b[self.p] & 3
        n = [1, 2, 4, 8][m]
        v = int.from_bytes(self.take(n), 'little') >> 2
        return v
    def one(self, t):
        if t in FMT: return struct.unpack(FMT[t], self.take(struct.calcsize(FMT[t])))[0]
        if t == T_STR: return self.take(self.varint())
        if t == T_BOOL: return self.take(1)[0] != 0
        if t == T_OBJ: return self.obj()
        raise ValueError('type %d' % t)
    def val(self):
        t = self.take(1)[0]
        if t & 0x80:
            return [self.one(t & 0x7f) for _ in range(self.varint())]
        return self.one(t)
    def obj(self):
        d = {}
        for _ in range(self.varint()):
            k = self.take(self.take(1)[0]).decode(errors='replace')
            d[k] = self.val()
        return d

def decode(b):
    r = Reader(b)
    a, c, v = struct.unpack('<IIB', r.take(9))
    if a != 0x01011101 or c != 0x01020101: raise ValueError('bad storage sig')
    return r.obj()

# ---- levin framing ----
def recv_exact(s, n):
    buf = b''
    while len(buf) < n:
        c = s.recv(n - len(buf))
        if not c: raise ConnectionError('eof')
        buf += c
    return buf

def send_req(s, cmd, body, want_resp=True):
    s.sendall(HDR.pack(SIG, len(body), want_resp, cmd, 0, 1, 1) + body)

def recv_until(s, cmd, max_frames=20):
    for _ in range(max_frames):
        sig, cb, ret, c, rc, flags, ver = HDR.unpack(recv_exact(s, HDR.size))
        if sig != SIG or cb > 4 * 1024 * 1024: raise ValueError('bad levin')
        body = recv_exact(s, cb)
        if c == cmd and flags & 2:
            return rc, body
    raise ValueError('no response')

def fmt_addr(a):
    t = a.get('type'); ad = a.get('addr', {})
    if t == 1:
        ip = str(ipaddress.IPv4Address(struct.pack('<I', ad['m_ip'])))
        return 'ipv4', ip, ad['m_port']
    if t == 2:
        return 'ipv6', str(ipaddress.IPv6Address(ad['addr'])), ad['m_port']
    if t in (3, 4):
        return ('i2p' if t == 3 else 'tor'), ad.get('host', b'').decode(errors='replace'), ad.get('port', 0)
    return 'other', repr(a), 0

def connect(host, port, timeout):
    s = socket.create_connection((host, port), timeout=timeout)
    s.settimeout(timeout)
    return s

def handshake(host, port, timeout=10):
    """Returns dict: peer_id, height, my_port, rpc_port, support_flags, pruning_seed, peers[list of (kind, ip, port, last_seen, id)]
    last_seen is None when the field is absent (stock monerod omits it; a sent 0 is not stock)."""
    body = encode({
        'node_data': {
            'network_id': NETWORK_ID,
            'peer_id': Typed(T_U64, int.from_bytes(os.urandom(8), 'little')),
            'my_port': Typed(T_U32, 0),
            'support_flags': Typed(T_U32, 1),
        },
        'payload_data': {
            'current_height': Typed(T_U64, 1),
            'cumulative_difficulty': Typed(T_U64, 1),
            'cumulative_difficulty_top64': Typed(T_U64, 0),
            'top_id': GENESIS,
            'top_version': Typed(T_U8, 1),
            'pruning_seed': Typed(T_U32, 0),
        },
    })
    s = connect(host, port, timeout)
    try:
        send_req(s, CMD_HANDSHAKE, body)
        rc, rb = recv_until(s, CMD_HANDSHAKE)
    finally:
        s.close()
    if rc < 0: raise ValueError('handshake rc %d' % rc)
    d = decode(rb)
    nd, pd = d.get('node_data', {}), d.get('payload_data', {})
    if nd.get('network_id') != NETWORK_ID: raise ValueError('wrong network')
    peers = []
    for e in d.get('local_peerlist_new', []) or []:
        kind, ip, p = fmt_addr(e.get('adr', {}))
        peers.append((kind, ip, p, e.get('last_seen'), '%016x' % e.get('id', 0), e.get('rpc_port', 0), e.get('pruning_seed', 0)))
    return dict(peer_id='%016x' % nd.get('peer_id', 0), my_port=nd.get('my_port'), rpc_port=nd.get('rpc_port', 0),
                support_flags=nd.get('support_flags', 0), height=pd.get('current_height'),
                top_version=pd.get('top_version'), pruning_seed=pd.get('pruning_seed', 0), peers=peers)

def ping(host, port, timeout=10):
    """Same check monerod's try_ping does. Returns remote peer_id hex or raises."""
    s = connect(host, port, timeout)
    try:
        send_req(s, CMD_PING, encode({}))
        rc, rb = recv_until(s, CMD_PING)
    finally:
        s.close()
    d = decode(rb)
    if d.get('status') != b'OK': raise ValueError('ping status %r' % d.get('status'))
    return '%016x' % d.get('peer_id', 0)

if __name__ == '__main__':
    import sys, json
    h, p = sys.argv[1], int(sys.argv[2])
    print('ping', ping(h, p))
    r = handshake(h, p)
    print(json.dumps({k: v for k, v in r.items() if k != 'peers'}), len(r['peers']), 'peers')
    for x in r['peers'][:5]: print(x)

def peer_entry(ip, port, peer_id=0, pruning_seed=0, rpc_port=0):
    """peerlist_entry for an IPv4 peer, as sent in handshake/timed-sync responses."""
    m_ip = struct.unpack('<I', ipaddress.IPv4Address(ip).packed)[0]
    e = {'adr': {'type': Typed(T_U8, 1), 'addr': {'m_ip': Typed(T_U32, m_ip), 'm_port': Typed(T_U16, port)}},
         'id': Typed(T_U64, peer_id)}
    if pruning_seed: e['pruning_seed'] = Typed(T_U32, pruning_seed)
    if rpc_port: e['rpc_port'] = Typed(T_U16, rpc_port)
    return e
