import os,sys,json,hashlib,tarfile,shutil
from pathlib import Path
name=sys.argv[1];args=sys.argv[2:];base=Path(os.environ['MOCK_BASE_WIN']);u=str(base.resolve()).replace('\\','/');u=('/'+u[0].lower()+u[2:]) if len(u)>1 and u[1]==':' else u;scenario=os.environ['MOCK_SCENARIO'];core=base/'ts/bin/tailscaled';running=base/'running'
def out(x):os.write(1,(str(x)+'\n').encode())
def isnew():return b'CORE_NEW' in core.read_bytes()
def fail(x=1):sys.exit(x)
if name=='pidof':
 if running.exists():out('111')
 else:fail()
elif name=='ip':
 if 'rule' in args:
  out('12500: from all to '+('fd7a:115c:a1e0::/48' if '-6' in args else '100.64.0.0/10')+' lookup 52')
  out('13001: not from all fwmark 0x10020000/0x1e000000 lookup 52')
 elif 'addr' in args:out('1: tailscale0 inet6 fd7a:115c:a1e0::1/128 scope global')
 else:out('1: tailscale0 UP')
elif name=='id':out(0)
elif name=='uname':out('aarch64')
elif name=='getenforce':out('Enforcing')
elif name=='timeout':os.execv(args[1],args[1:]) if False else fail(99)
elif name=='date':
 if args==['+%s']:
  f=base/'clock';t=int(f.read_text()) if f.exists() else 1000;t+=80 if scenario=='stuck' else 1;f.write_text(str(t));out(t)
 else:out('20261022-TEST')
elif name=='readlink':
 s=args[-1].replace('\\','/').rstrip('/');bn=Path(s).name
 if s.endswith('/ts/bin/tailscaled') or s.endswith('/ts/bin/tailscale'):out(u+'/ts/bin/tailscaled')
 elif s.endswith('/proc/111/exe'):
  if not running.exists():fail()
  out(u+'/ts/bin/tailscaled'+(' (deleted)' if scenario=='survivor-deleted' and (base/'stopped').exists() else ''))
 elif s.endswith('/ns/net'):out('net:[4000000000]')
 else:out(s)
elif name in ('mkdir','rmdir','touch','cp','mv'):
 try:
  paths=[Path(a) for a in args if not a.startswith('-')]
  if name=='mkdir':
   for p in paths:p.mkdir(parents='-p' in args,exist_ok='-p' in args)
  elif name=='rmdir':
   for p in paths:p.rmdir()
  elif name=='touch':
   for p in paths:p.touch()
  elif name=='cp':shutil.copy2(paths[-2],paths[-1])
  elif name=='mv':os.replace(paths[-2],paths[-1])
 except Exception as e:out(repr(e));fail()
elif name=='sha256sum':
 if args[0]=='-c':
  for line in Path(args[1]).read_text().splitlines():
   digest,filename=line.split('  ',1)
   if hashlib.sha256(Path(filename).read_bytes()).hexdigest()!=digest:fail()
   out(filename+': OK')
 else:
  for f in args:out(hashlib.sha256(Path(f).read_bytes()).hexdigest()+'  '+f)
elif name=='tar':
 output=Path(args[1]);source=Path(args[args.index('-C')+1])
 with tarfile.open(output,'w') as t:
  for f in source.rglob('*'):
   rel=f.relative_to(source)
   if any(x in ('backups','run') for x in rel.parts) or f.name.endswith('.sock'):continue
   if f.is_file():t.add(f,arcname=str(rel),recursive=False)
elif name=='ls':out('u:object_r:system_file:s0 '+args[-1])
elif name=='chmod':
 for f in args[1:]:Path(f).chmod(int(args[0],8))
elif name=='chcon':pass
elif name=='sleep':pass
elif name=='nohup':pass
elif name=='helper':
 identity={'uid':0,'euid':0,'gid':0,'egid':0,'groups':[0],'context':'u:r:ksu:s0','netns':'net:[4000000000]'}
 if scenario=='identity-mismatch':identity['context']='u:r:wrong:s0'
 out(json.dumps({'test':'identity','ok':True,'value':identity}))
 if scenario=='precheck-fail' or (scenario=='postcheck-fail' and isnew()):fail()
elif name=='cli':
 if 'version' in args or '--version' in args:out('1.104.1-magisk-v2-local' if isnew() else '1.90.6-15')
 elif 'prefs' in args:out(json.dumps({'RunSSH':scenario=='ssh-enabled'}))
 elif 'status' in args:
  if not running.exists():fail()
  out(json.dumps({'Version':'1.104.1-magisk-v2-local' if isnew() else '1.90.6-15','BackendState':'Starting' if isnew() and scenario=='stuck' else 'Running','Self':{'ID':'node-test','TailscaleIPs':['100.64.1.2','fd7a:115c:a1e0::1'],'Online':True,'Relay':'hkg'}}))
 else:fail(2)
elif name=='newcore':out('1.104.1-magisk-v2-local')
elif name=='service':
 (base/'service-events').open('a').write(args[0]+(' NEW' if isnew() else ' OLD')+'\n')
 if args[0]=='stop':
  (base/'stopped').touch()
  if scenario!='survivor-deleted':running.unlink(missing_ok=True)
 elif args[0]=='start':
  if isnew():
   (base/'ts/tailscaled.state').write_text('SYNTHETIC-MIGRATED-STATE')
   if scenario=='start-fail':fail()
  running.touch()
 else:fail(2)
elif name=='jq':
 try:
  pos=0;vars={}
  while args[pos] in ('-s','-e'):pos+=1
  while args[pos]=='--arg':vars[args[pos+1]]=args[pos+2];pos+=3
  expr=args[pos].strip();file=Path(args[pos+1]);data=[json.loads(x) for x in file.read_text().splitlines() if x]
  if expr.startswith('select(.test') or expr.startswith('any(.[]'):
   ok=any(x.get('test')=='identity' and x['ok'] and x['value']['uid']==0 and x['value']['euid']==0 and x['value']['gid']==0 and x['value']['egid']==0 and x['value']['context']==vars['ctx'] and x['value']['netns']==vars['ns'] for x in data)
  elif 'RunSSH' in expr:ok=not data[0].get('RunSSH',False)
  elif '.Version' in expr:ok=data[0]['Version']==vars['target']
  elif 'Self.ID' in expr:ok=data[0]['Self']==json.loads(Path(args[pos+2]).read_text())['Self']
  elif 'Self.Online' in expr:ok=data[0]['BackendState']=='Running' and data[0]['Self']['Online'] and bool(data[0]['Self']['Relay'])
  else:ok=data[0]['BackendState']=='Running'
  out('true' if ok else 'false');fail(0 if ok else 1)
 except Exception as e:out(repr(e));fail(2)
else:out('UNKNOWN '+name);fail(2)
