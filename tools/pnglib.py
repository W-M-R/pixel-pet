"""极小 PNG 读写。只支持 8bit RGBA/RGB/灰度，够处理像素素材。"""
import zlib, struct

def load(path):
    d = open(path, 'rb').read()
    assert d[:8] == b'\x89PNG\r\n\x1a\n', "not png"
    i = 8; idat = b''; w = h = ct = None; pal = None; trns = None
    while i < len(d):
        ln = struct.unpack('>I', d[i:i+4])[0]; typ = d[i+4:i+8]; dat = d[i+8:i+8+ln]
        if typ == b'IHDR': w, h, bd, ct = struct.unpack('>IIBB', dat[:10])
        elif typ == b'PLTE': pal = dat
        elif typ == b'tRNS': trns = dat
        elif typ == b'IDAT': idat += dat
        i += 12 + ln
    ch = {0:1, 2:3, 3:1, 4:2, 6:4}[ct]
    raw = zlib.decompress(idat)
    st = w * ch; out = bytearray(); prev = bytearray(st); pos = 0
    for _ in range(h):
        f = raw[pos]; pos += 1
        line = bytearray(raw[pos:pos+st]); pos += st
        for x in range(st):
            a = line[x-ch] if x >= ch else 0
            b = prev[x]
            c = prev[x-ch] if x >= ch else 0
            if f == 1: line[x] = (line[x] + a) & 255
            elif f == 2: line[x] = (line[x] + b) & 255
            elif f == 3: line[x] = (line[x] + (a+b)//2) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p-a), abs(p-b), abs(p-c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[x] = (line[x] + pr) & 255
        out += line; prev = line
    # 统一转 RGBA
    rgba = bytearray(w*h*4)
    for j in range(w*h):
        if ct == 6:
            rgba[j*4:j*4+4] = out[j*4:j*4+4]
        elif ct == 2:
            rgba[j*4:j*4+3] = out[j*3:j*3+3]; rgba[j*4+3] = 255
        elif ct == 3:
            idx = out[j]
            rgba[j*4:j*4+3] = pal[idx*3:idx*3+3]
            rgba[j*4+3] = trns[idx] if trns and idx < len(trns) else 255
        elif ct == 0:
            v = out[j]; rgba[j*4:j*4+3] = bytes([v,v,v]); rgba[j*4+3] = 255
        elif ct == 4:
            v, a = out[j*2], out[j*2+1]
            rgba[j*4:j*4+3] = bytes([v,v,v]); rgba[j*4+3] = a
    return w, h, rgba

def save(path, w, h, rgba):
    raw = b''.join(b'\x00' + bytes(rgba[y*w*4:(y+1)*w*4]) for y in range(h))
    def ck(t, d):
        return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t+d) & 0xffffffff)
    png = (b'\x89PNG\r\n\x1a\n'
           + ck(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
           + ck(b'IDAT', zlib.compress(bytes(raw), 9))
           + ck(b'IEND', b''))
    open(path, 'wb').write(png)

def px(rgba, w, x, y):
    i = (y*w + x)*4
    return tuple(rgba[i:i+4])

def setpx(rgba, w, x, y, c):
    i = (y*w + x)*4
    rgba[i:i+4] = bytes(c)
