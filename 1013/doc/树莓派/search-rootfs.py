import ctypes, struct, sys, time
GENERIC_READ=0x80000000; OPEN_EXISTING=3; FILE_SHARE_READ=1; FILE_SHARE_WRITE=2
k=ctypes.WinDLL("kernel32", use_last_error=True)
k.CreateFileW.restype=ctypes.c_void_p
k.CreateFileW.argtypes=[ctypes.c_wchar_p,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_void_p,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_void_p]
k.SetFilePointerEx.restype=ctypes.c_int
k.SetFilePointerEx.argtypes=[ctypes.c_void_p,ctypes.c_longlong,ctypes.c_void_p,ctypes.c_uint32]
k.ReadFile.restype=ctypes.c_int
k.ReadFile.argtypes=[ctypes.c_void_p,ctypes.c_void_p,ctypes.c_uint32,ctypes.POINTER(ctypes.c_uint32),ctypes.c_void_p]
PART=545259520
h=k.CreateFileW(r"\\.\PhysicalDrive2",GENERIC_READ,FILE_SHARE_READ|FILE_SHARE_WRITE,None,OPEN_EXISTING,0,None)
def rd(off,n):
    S=512; off=PART+off; start=(off//S)*S; end=((off+n+S-1)//S)*S
    k.SetFilePointerEx(h,start,None,0)
    b=ctypes.create_string_buffer(end-start); got=ctypes.c_uint32(0)
    r=k.ReadFile(h,b,end-start,ctypes.byref(got),None)
    return b.raw[:got.value][off-start:off-start+n]
sb=rd(1024,4096)[:1024]
bs=1024<<struct.unpack_from("<I",sb,24)[0]; ipg=struct.unpack_from("<I",sb,40)[0]; isz=struct.unpack_from("<H",sb,88)[0]
def gd(g): return struct.unpack_from("<III",rd(bs+g*32,32),0)
def inode(ino):
    g=(ino-1)//ipg; i=(ino-1)%ipg; _,_,itab=gd(g)
    raw=rd(itab*bs+i*isz,isz)
    return struct.unpack_from("<H",raw,0)[0], struct.unpack_from("<I",raw,4)[0], list(struct.unpack_from("<15I",raw,40)), raw
def extents(node,depth):
    out=[]; n=struct.unpack_from("<H",node,2)[0]
    for kk in range(n):
        o=12+kk*12
        if depth==0:
            eb,el,hi,lo=struct.unpack_from("<IHHI",node,o); out.append(((hi<<32)|lo,el&0x7FFF))
        else:
            eb,lo,hi=struct.unpack_from("<IIH",node,o); out.extend(extents(rd(((hi<<32)|lo)*bs,bs),depth-1))
    return out
def readf(ino, cap=400000):
    mode,size,blk,raw=inode(ino)
    if size==0: return b""
    if (blk[0]&0xFFFF)==0xF30A:
        node=raw[40:100]; depth=struct.unpack_from("<H",node,6)[0]
        data=b"".join(rd(p*bs,c*bs) for p,c in extents(node,depth))
    else:
        data=b"".join(rd(p*bs,bs) for p in blk[:12] if p)
    return data[:min(size,cap)]
def ls_ino(ino):
    raw=readf(ino, 400000); pos=0; out=[]
    while pos+8<=len(raw):
        i2,rl,nl=struct.unpack_from("<IHB",raw,pos)
        nm=raw[pos+8:pos+8+nl].decode("utf-8","replace")
        if i2: out.append((nm,i2))
        if rl==0: break
        pos+=rl
    return out
NEEDLE=b"Not allowed at this time"
SKIP={"/proc","/sys","/dev","/run","/var/lib/docker","/var/lib/containerd","/usr/lib","/usr/share","/var/cache","/boot","/srv","/media","/mnt"}
found=[]; scanned=0; t0=time.time()
def walk(ino, path, depth):
    global scanned
    if path in SKIP or depth>8: return
    try: entries=ls_ino(ino)
    except Exception: return
    for nm,i2 in entries:
        if nm in (".",".."): continue
        p = path.rstrip("/")+"/"+nm
        if p in SKIP: continue
        try:
            mode,size,blk,raw=inode(i2)
        except Exception: continue
        if (mode & 0o170000)==0o040000:
            walk(i2,p,depth+1)
        elif (mode & 0o170000)==0o100000 and 0 < size <= 300000:
            scanned+=1
            try: data=readf(i2)
            except Exception: continue
            if NEEDLE in data:
                idx=data.find(NEEDLE)
                ctx=data[max(0,idx-120):idx+len(NEEDLE)+120].decode("utf-8","replace")
                found.append((p,size,ctx))
                print(f"### 命中: {p} ({size} 字节)")
                print("    ..." + ctx.replace("\n"," | ") + "...")
walk(2,"",0)
print(f"\n扫描完成：检查了 {scanned} 个文件，耗时 {time.time()-t0:.0f}s，命中 {len(found)} 处")
k.CloseHandle(h)
