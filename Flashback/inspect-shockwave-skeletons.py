#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Compare W3D skeleton layouts with/without optional axis limits.

Usage: python3 inspect-shockwave-skeletons.py COLLECTION OUTPUT.json
This structural scan checks byte alignment, names, and parent indices. It is
not a gameplay test; the runtime parser has its own executable regression test.
"""
import hashlib,json,re,struct,zlib,sys
from pathlib import Path
root=Path(sys.argv[1]).resolve(); output=Path(sys.argv[2]); seen=set(); results=[]; streams=0; files=0

def inspect(data,file,offset):
 global streams
 at=data[:256].find(b'IFX\0')
 if at<0:return
 d=data[at:];digest=hashlib.sha256(d).hexdigest()
 if digest in seen:return
 seen.add(digest);streams+=1
 p=8+struct.unpack_from('<I',d,4)[0]
 while p+8<=len(d):
  typ,size=struct.unpack_from('<II',d,p);p+=8
  if p+size>len(d):break
  if typ==0xffffff4b:
   b=d[p:p+size]
   try:
    n=struct.unpack_from('<H',b,0)[0];name=b[2:2+n].decode('latin1');count=struct.unpack_from('<I',b,2+n)[0]
    rec=dict(file=str(file.relative_to(root)),stream_offset=offset,sha256=digest,name=name,bones=count)
    if count>100000:continue
    for optional in (False,True):
     q=6+n;added=0
     try:
      for i in range(count):
       length=struct.unpack_from('<H',b,q)[0];q+=2
       if not 0<length<1024:raise ValueError(f'invalid name length {length} at bone {i}')
       name_bytes=b[q:q+length];q+=length
       if any(c<32 for c in name_bytes):raise ValueError(f'invalid name at bone {i}')
       parent,*values,attrs=struct.unpack_from('<I8fI',b,q);q+=40
       if parent!=0xffffffff and parent>=i:raise ValueError(f'invalid parent {parent} at bone {i}')
       if optional:
        extra=8*(attrs&(attrs>>3)&7).bit_count();q+=extra;added+=extra
       if q>len(b):raise ValueError('truncated optional data')
      rec['after' if optional else 'before']=dict(ok=True,tail=len(b)-q,optional_bytes=added)
     except (ValueError,struct.error) as e:rec['after' if optional else 'before']=dict(ok=False,error=str(e))
    results.append(rec)
   except (ValueError,struct.error) as e:results.append(dict(file=str(file.relative_to(root)),error=str(e)))
  p=(p+size+3)&~3
for f in root.rglob('*'):
 if not f.is_file() or f.suffix.lower() not in ('.dcr','.dir','.dxr','.cct','.cst','.w3d'):continue
 data=f.read_bytes();files+=1
 inspect(data,f,0)
 if f.suffix.lower()=='.w3d':continue
 for m in re.finditer(b'\x78[\x01\x5e\x9c\xda]',data):
  try:
   z=zlib.decompressobj();raw=z.decompress(data[m.start():],32*1024*1024)
   if raw[:256].find(b'IFX\0')>=0:inspect(raw,f,m.start())
  except (ValueError,zlib.error,struct.error):pass
report=dict(files=files,unique_w3d_streams=streams,skeletons=results)
output.write_text(json.dumps(report,indent=2)+'\n')
print('files',files,'unique W3D',streams,'skeletons',len(results),'before passes',sum(x.get('before',{}).get('ok',False) for x in results),'after passes',sum(x.get('after',{}).get('ok',False) for x in results))
for x in results:
 if x.get('after',{}).get('ok')!=x.get('before',{}).get('ok'):print(x['file'],x['name'],x['bones'],x['before'],x['after'])
