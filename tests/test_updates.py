"""Control-flow simulations only. Android, SELinux, jq and networking are mocked."""
import os, sys, subprocess, json, hashlib, tempfile, shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SH=os.environ.get('TEST_SH') or shutil.which('sh')
if not SH:raise SystemExit('Set TEST_SH to a POSIX shell')
def unix(p):
 s=str(Path(p).resolve()).replace('\\','/');return '/'+s[0].lower()+s[2:] if len(s)>1 and s[1]==':' else s
def write(p,s):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s,encoding='utf-8',newline='\n');p.chmod(0o755)
def launch(name):return '#!/bin/sh\nexec "'+unix(sys.executable)+'" "'+unix(ROOT/'tests/mock_commands.py')+'" '+name+' "$@"\n'
results=[]
with tempfile.TemporaryDirectory(prefix='ts-module-tests-') as tmp:
 for scenario in ['success','precheck-fail','identity-mismatch','ssh-enabled','start-fail','stuck','postcheck-fail','survivor-deleted','same-core','downgrade','bad-checksum','missing-payload']:
  b=Path(tmp)/scenario;b.mkdir();u=unix(b);(b/'running').touch()
  for rel in ['ts/bin','ts/scripts','proc/111/attr','proc/111/ns','pkg/updater/scripts','pkg/updater/bin','mockbin']:(b/rel).mkdir(parents=True)
  for name in ['id','uname','getenforce','date','readlink','ls','chcon','sleep','nohup','jq','sha256sum','tar','mkdir','rmdir','touch','cp','mv','pidof','ip','chmod']:write(b/'mockbin'/name,launch(name))
  write(b/'mockbin/timeout','#!/bin/sh\nshift\nexec "$@"\n')
  write(b/'mockbin/busybox','#!/bin/sh\nexit 0\n')
  for p in (ROOT/'updater/scripts').glob('*.sh'):
   src=p.read_text(encoding='utf-8').replace('TS=/data/adb/tailscale','TS="'+u+'/ts"').replace('/proc/',u+'/proc/')
   write(b/'pkg/updater/scripts'/p.name,src)
  oldcore=(launch('cli')+'# CORE_OLD\n').encode();newcore=(launch('cli')+'# CORE_NEW\n').encode()
  (b/'ts/bin/tailscaled').write_bytes(oldcore);(b/'ts/bin/tailscaled').chmod(0o755)
  write(b/'ts/bin/tailscale',launch('cli'));write(b/'ts/bin/jq',launch('jq'))
  oldstate=b'SYNTHETIC-OLD-STATE';(b/'ts/tailscaled.state').write_bytes(oldstate)
  write(b/'ts/settings.sh','# original customized settings\n');write(b/'ts/scripts/tailscaled.service',launch('service'))
  P=b/'pkg/updater/bin'
  write(P/'tailscaled-arm64',launch('newcore')+'# CORE_NEW\n')
  write(P/'android-core-check-arm64',launch('helper'))
  if scenario=='same-core':(P/'tailscaled-arm64').write_bytes(oldcore)
  if scenario=='downgrade':write(P/'tailscaled-arm64','#!/bin/sh\necho 1.80.0\n')
  sums=''.join(hashlib.sha256((P/x).read_bytes()).hexdigest()+'  '+x+'\n' for x in ['tailscaled-arm64','android-core-check-arm64'])
  (P/'SHA256SUMS-arm64').write_text(sums,encoding='utf-8',newline='\n')
  if scenario=='bad-checksum':(P/'tailscaled-arm64').write_bytes(newcore+b'CORRUPT')
  if scenario=='missing-payload':(P/'tailscaled-arm64').unlink()
  (b/'proc/111/cmdline').write_bytes(b'tailscaled\0-no-logs-no-support\0')
  (b/'proc/111/status').write_text('Gid:\t0\t0\t0\t0\n');(b/'proc/111/attr/current').write_text('u:r:ksu:s0')
  (b/'proc/111/exe').touch();(b/'proc/111/ns/net').touch()
  env=os.environ.copy();env.update(MOCK_BASE_WIN=str(b),MOCK_SCENARIO=scenario)
  env['PATH']=str(b/'mockbin')+os.pathsep+str(Path(SH).parent)+os.pathsep+env['PATH']
  p=subprocess.run([SH,unix(b/'pkg/updater/scripts/prepare.sh'),unix(b/'pkg'),'arm64'],env=env,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=60)
  core=(b/'ts/bin/tailscaled').read_bytes();state=(b/'ts/tailscaled.state').read_bytes()
  ok=(p.returncode==0 and b'CORE_NEW' in core and state==b'SYNTHETIC-MIGRATED-STATE') if scenario=='success' else (core==oldcore and state==oldstate and (p.returncode==0 if scenario=='same-core' else p.returncode!=0))
  if scenario in ['same-core','downgrade','bad-checksum','missing-payload','precheck-fail','identity-mismatch','ssh-enabled']:ok=ok and not (b/'service-events').exists()
  if scenario in ['start-fail','stuck','postcheck-fail']:ok=ok and any(x.name=='RECOVERED' for x in (b/'ts/backups').rglob('*')) and (b/'running').exists()
  row={'scenario':scenario,'passed':bool(ok)};results.append(row);print(json.dumps(row),flush=True)
  if not ok:print(p.stdout,p.stderr,flush=True)
  if scenario=='success' and ok:
   B=next(x for x in (b/'ts/backups').glob('upgrade-*') if (x/'COMMITTED').exists())
   events=(b/'service-events').read_bytes();saved=(B/'core.old').read_bytes();(B/'core.old').write_bytes(saved+b'CORRUPTION')
   q=subprocess.run([SH,unix(B/'rollback.sh'),unix(B)],env=env,capture_output=True,timeout=30)
   passed=q.returncode!=0 and (b/'ts/bin/tailscaled').read_bytes()==core and (b/'service-events').read_bytes()==events
   results.append({'scenario':'corrupt-backup-refused-before-stop','passed':passed});print(json.dumps(results[-1]),flush=True)
   (B/'core.old').write_bytes(saved)
   q=subprocess.run([SH,unix(B/'rollback.sh'),unix(B)],env=env,capture_output=True,timeout=30)
   passed=q.returncode==0 and (b/'ts/bin/tailscaled').read_bytes()==oldcore and (b/'ts/tailscaled.state').read_bytes()==oldstate
   results.append({'scenario':'manual-rollback','passed':passed});print(json.dumps(results[-1]),flush=True)
if os.environ.get('TEST_REPORT'):Path(os.environ['TEST_REPORT']).write_text(json.dumps({'scope':__doc__,'results':results},indent=2),encoding='utf-8')
raise SystemExit(0 if all(r['passed'] for r in results) else 1)
