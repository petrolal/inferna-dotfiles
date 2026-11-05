#!/usr/bin/env python3
"""Responsive system showcase, rendered with live Fastfetch data."""
import json, os, re, shutil, subprocess, sys, tomllib
from pathlib import Path
from datetime import datetime
ROOT=Path.home()/'.config/fastfetch'
CURRENT=Path.home()/'.local/state/inferna/current/theme'
try: theme=tomllib.loads((CURRENT/'colors.toml').read_text())
except (OSError,ValueError): theme={}
def brand_name():
    """Same name as the menu title: "root": {"title": ...} in Inferna's menu extension file."""
    for p in (
        Path.home() / '.config/inferna/extensions/inferna-menu.jsonc',
        Path.home() / '.config/inferna/extensions/inferna-menu.jsonc',
    ):
        try:
            if p.exists():
                text = p.read_text()
                m = re.search(r'"root"\s*:\s*\{[^}]*?"title"\s*:\s*"([^"]+)"', text)
                if m: return m.group(1)
        except Exception:
            pass
    return 'INFERNA'
BRAND=brand_name()
def color(key,default):
    value=theme.get(key,default).lstrip('#')
    try: return '\033[38;2;{};{};{}m'.format(*[int(value[i:i+2],16) for i in (0,2,4)])
    except ValueError: return '\033[39m'
A=color('accent','#eabb6a'); C=color('cyan','#6fbdd0'); F=color('foreground','#dce8e4'); M=color('muted','#5d7d84'); G=color('green','#8db598'); R='\033[0m'; B='\033[1m'
ansi=re.compile(r'\x1b\[[0-9;]*m')
def width(s): return len(ansi.sub('',s))
def pad(s,n): return s+' '*max(0,n-width(s))
def clip(s,n): return str(s) if len(str(s))<=n else str(s)[:max(0,n-1)]+'…'
cols=shutil.get_terminal_size((120,40)).columns
try:
    with open('/dev/tty') as tty: cols=os.get_terminal_size(tty.fileno()).columns
except OSError: pass
if '--width' in sys.argv: cols=int(sys.argv[sys.argv.index('--width')+1])
cols=max(40,cols-2)
modules='os:host:cpu:gpu:memory:swap:cpuusage:disk:netio:display:terminal:terminalfont:wm:packages:uptime:processes:loadavg:battery:kernel:board:bios:theme:icons:cursor'
try:
    result=subprocess.run(['fastfetch','--config','none','--structure',modules,'--format','json'],capture_output=True,text=True,timeout=12,check=True)
    data={x['type'].lower():x.get('result') for x in json.loads(result.stdout)}
except (subprocess.SubprocessError,ValueError) as e:
    print('Dashboard data unavailable:',e); sys.exit(1)
def d(k): return data.get(k) or {}
def first(k): return next(iter(data.get(k) or []),{})
def size(n): return f'{n/1024**3:.1f} GiB'
def rate(n): return f'{n/1024:.1f} KiB/s'
def run(args,fallback='unknown'):
    try: return subprocess.check_output(args,text=True,stderr=subprocess.DEVNULL,timeout=2).strip()
    except (OSError,subprocess.SubprocessError): return fallback
name=run(['inferna','theme','current'],CURRENT.resolve().name)
cpu=d('cpu'); gpu=first('gpu'); mem=d('memory'); swap=d('swap'); disk=next((x for x in data.get('disk',[]) if x['mountpoint']=='/'),{})
net=first('netio'); bat=first('battery'); display=first('display'); wm=d('wm'); kernel=d('kernel')
up=int(d('uptime').get('uptime',0)/1000); proc=d('processes'); usage=data.get('cpuusage') or [0]
cores=cpu.get('cores',{})
def meter(p):
    p=max(0,min(100,float(p))); filled=round(p/100*16)
    return C+'━'*filled+M+'─'*(16-filled)+F+f' {p:4.0f}%'
def resource(key):
    v=d(key)
    if isinstance(v,list): v={k:sum(x.get(k,0) for x in v) for k in ('total','used')}
    total=v.get('total',0); used=v.get('used',0)
    return meter(used/total*100 if total else 0),f'{size(used)} / {size(total)}'
hardware=[('Model',d('host').get('name','')),('Processor',cpu.get('cpu','')),('Topology',f"{cores.get('physical','?')} cores / {cores.get('logical','?')} threads"),('Boost',f"{cpu.get('frequency',{}).get('max',0)/1000:.2f} GHz"),('Graphics',gpu.get('name','')),('GPU driver',gpu.get('driver','')),('Display',f"{display.get('output',{}).get('width','?')} × {display.get('output',{}).get('height','?')}  /  {display.get('output',{}).get('refreshRate',0):.0f} Hz"),('Board',d('board').get('name','')),('Firmware',d('bios').get('version',''))]
ram_meter,ram_size=resource('memory'); swap_meter,swap_size=resource('swap'); db=disk.get('bytes',{}); total=db.get('total',1); used=total-db.get('free',total)
telemetry=[('CPU',meter(sum(usage)/len(usage))),('Memory',ram_meter),('Allocated',ram_size),('Swap',swap_meter),('Swap used',swap_size),('Root disk',meter(used/total*100)),('Capacity',f'{size(used)} / {size(total)}'),('Filesystem',disk.get('filesystem','')),('Processes',f"{proc.get('processes','?')} / {proc.get('threads','?')} threads"),('Load avg','  '.join(f'{x:.2f}' for x in (data.get('loadavg') or []))),('Battery',f"{bat.get('capacity',0):.0f}%  /  {', '.join(bat.get('status',[]))}")]
system=[('Distribution',f'{BRAND} · NixOS'),('Kernel',kernel.get('release','')),('Architecture',kernel.get('architecture','')),('Uptime',f'{up//86400}d {up%86400//3600}h {up%3600//60}m'),('Packages',str(d('packages').get('all','?'))),('Session',wm.get('protocolName','')),('Snapshot',datetime.now().strftime('%H:%M:%S  /  %d %b %Y'))]
term=d('terminal'); font=d('terminalfont')
# The outer Fastfetch process otherwise looks like a terminal to the inner one.
terminal_name=''
pid=os.getpid()
for _ in range(32):
    try:
        comm=Path(f'/proc/{pid}/comm').read_text().strip()
        clean=comm.lstrip('.').removesuffix('-wrapped')
        if clean in ('foot','footclient','kitty','alacritty','ghostty','wezterm-gui','konsole','xterm'):
            terminal_name=clean; break
        status=Path(f'/proc/{pid}/status').read_text()
        pid=int(re.search(r'^PPid:\s+(\d+)',status,re.M).group(1))
        if pid<=1: break
    except (OSError,AttributeError,ValueError): break
terminal_label=terminal_name or 'not detected'
font_label='terminal default'
if terminal_name in ('foot','footclient'):
    try:
        conf=(Path.home()/'.config/foot/foot.ini').read_text()
        font_label=re.search(r'^font=(.+)$',conf,re.M).group(1).replace(':size=',' / ')+'pt'
    except (OSError,AttributeError): pass
elif terminal_name == 'kitty':
    try:
        conf=(Path.home()/'.config/kitty/kitty.conf').read_text()
        fam = re.search(r'^\s*font_family\s+(.+)$', conf, re.M)
        sz = re.search(r'^\s*font_size\s+([0-9.]+)', conf, re.M)
        fam_str = fam.group(1).strip() if fam else 'JetBrainsMono Nerd Font'
        sz_str = sz.group(1).strip() if sz else '10'
        font_label = f"{fam_str} / {sz_str}pt"
    except (OSError,AttributeError): pass


desktop=[('Theme',name),('Compositor',wm.get('prettyName','')+' '+wm.get('version','')),('Terminal',terminal_label),('Font',font_label),('Shell',Path(os.environ.get('SHELL','bash')).name),('GTK',d('theme').get('theme2','')),('Icons',d('icons').get('icons2','')),('Cursor',d('cursor').get('theme',''))]
network=[('Interface',net.get('name','offline')),('Receive',rate(net.get('rxBytes',0))),('Transmit',rate(net.get('txBytes',0))),('RX / TX drops',f"{net.get('rxDrops',0)} / {net.get('txDrops',0)}")]
def card(title,rows,w):
    inner=w-4
    lines=[A+'╭─ '+B+title+R+A+' '+'─'*max(0,w-len(title)-5)+'╮'+R]
    for key,value in rows:
        if not value: continue
        if '\033' in str(value): content=C+f'{key:<12} '+F+str(value)
        else: content=C+f'{key:<12} '+F+clip(value,inner-13)
        lines.append(A+'│ '+pad(content,inner)+A+' │'+R)
    lines.append(A+'╰'+'─'*(w-2)+'╯'+R)
    return lines
def stack(*cards):
    lines=[]
    for c in cards:
        if lines: lines.append('')
        lines+=c
    return lines
logo_path=Path.home()/'.config/inferna/branding/about.txt'
if not logo_path.exists():
    logo_path=Path.home()/'.config/inferna/branding/about.txt'
logo=logo_path.read_text().splitlines() if logo_path.exists() else [BRAND]
lw=max(map(len,logo)); gap=3
print()
heading=' '.join(BRAND.upper())+'   /   '+name.upper()
print(B+A+heading+R)
subtitle='SYSTEM OVERVIEW   ·   HARDWARE / TELEMETRY / DESKTOP'
print(M+clip(subtitle,cols)+R)
print(M+'━'*cols+R)
print()
if cols>=lw+2*gap+100:
    cw=(cols-lw-2*gap)//2
    left=stack(card('01  HARDWARE',hardware,cw),card('02  LIVE TELEMETRY',telemetry,cw))
    right=stack(card('03  SYSTEM',system,cw),card('04  DESKTOP',desktop,cw),card('05  NETWORK',network,cw))
    logo_lines=[A+line+R for line in logo]
    logo_lines+=['',B+A+pad(' '.join(BRAND.upper()),lw)+R,C+pad(name,lw)+R]
    for i in range(max(len(logo_lines),len(left),len(right))):
        print(pad(logo_lines[i] if i<len(logo_lines) else '',lw)+' '*gap+pad(left[i] if i<len(left) else '',cw)+' '*gap+(right[i] if i<len(right) else ''))
else:
    for line in logo: print(A+line+R)
    print()
    if cols>=100:
        cw=(cols-gap)//2
        left=stack(card('01  HARDWARE',hardware,cw),card('02  LIVE TELEMETRY',telemetry,cw))
        right=stack(card('03  SYSTEM',system,cw),card('04  DESKTOP',desktop,cw),card('05  NETWORK',network,cw))
        for i in range(max(len(left),len(right))): print(pad(left[i] if i<len(left) else '',cw)+' '*gap+(right[i] if i<len(right) else ''))
    else:
        for title,rows in [('HARDWARE',hardware),('TELEMETRY',telemetry),('SYSTEM',system),('DESKTOP',desktop),('NETWORK',network)]:
            print('\n'.join(card(title,rows,cols))); print()
print()
print(M+'─'*cols+R)
print(A+'THEME PALETTE  '+''.join(color(k,v)+'████ ' for k,v in [('background','#0f1d22'),('muted','#5d7d84'),('cyan','#6fbdd0'),('accent','#eabb6a'),('green','#8db598'),('red','#dc665d'),('magenta','#c995a8'),('foreground','#dce8e4')])+R)
print(G+'● '+F+'SYSTEM ONLINE'+M+'   /   '+name+'   /   '+ 'LIVE DATA · CAPTURED ON RUN'+R)
print()
