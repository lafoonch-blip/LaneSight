"""Browser-based landmark verification tool (reliable fallback for the cv2 window, which opencv 5.0.0's
Cocoa HighGUI renders unreliably on macOS). Still a small LOCAL Python app: a stdlib http.server serves the
stabilized plates + a single-page labeler; it saves to the SAME `*.landmarks.json` schema with the SAME
safeguards (original-pixel coords, verified-only calibration, merge never clobbers verified, suggested vs
verified distinct). No external dependencies; no production-pipeline changes.

Run:
  python -m lanesight_core.cv.calib.label_server "<…>/calib_landmarks" [--port 8765] [--autofill]
then open the printed http://localhost:8765/ in Chrome.
"""
from __future__ import annotations
import os
import glob
import json
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from .landmarks import LandmarkSet
from .lane_geometry import CANONICAL
from .label_tool import ARM_ORDER, merge_existing_and_suggestions

STATE = {"dir": None, "autofill": False}


def _clip_ids():
    return sorted(os.path.basename(p)[:-len(".plate.png")]
                  for p in glob.glob(os.path.join(STATE["dir"], "*.plate.png")))


def _json_path(clip):
    return os.path.join(STATE["dir"], f"{clip}.landmarks.json")


def _plate_path(clip):
    return os.path.join(STATE["dir"], f"{clip}.plate.png")


def _stab_for(clip):
    base = "/Users/shaynel/Developer/LaneSight/10-25 training videos"
    for p in (os.path.join(base, f"{clip}_stab.pkl"), os.path.join(base, "_results", clip, f"{clip}_stab.pkl")):
        if os.path.exists(p):
            return p
    return None


def _load_clip(clip):
    import cv2
    img = cv2.imread(_plate_path(clip))
    h, w = img.shape[:2]
    jp = _json_path(clip)
    ls = LandmarkSet.from_json(jp) if os.path.exists(jp) else LandmarkSet.template(clip, (w, h))
    if STATE["autofill"]:
        stab = _stab_for(clip)
        if stab:
            from .autofill import autofill
            ls = merge_existing_and_suggestions(ls, autofill(stab, log=lambda *a, **k: None))
    return ls, (w, h)


def _geometry_meta():
    anchors = [n for n in ARM_ORDER if CANONICAL.world_point(n) is not None]
    intervals = list(CANONICAL.interval_landmarks().keys())
    return {"arm_order": ARM_ORDER, "anchors": anchors, "intervals": intervals}


PAGE = r"""<!doctype html><html><head><meta charset="utf-8"><title>LaneSight labeler</title>
<style>
 body{margin:0;background:#111;color:#eee;font:13px/1.4 system-ui;display:flex;height:100vh;overflow:hidden}
 #side{width:230px;flex:none;background:#181818;padding:8px;overflow:auto;border-right:1px solid #333}
 #main{flex:1;display:flex;flex-direction:column}
 #hud{background:#000;padding:6px 10px;font-weight:600;white-space:nowrap;overflow:hidden}
 canvas{flex:1;background:#000;cursor:crosshair;display:block}
 .lm{padding:3px 6px;border-radius:4px;cursor:pointer;display:flex;justify-content:space-between}
 .lm:hover{background:#2a2a2a}.armed{background:#064}.verified{color:#5f5}.suggested{color:#fc6}
 .ambiguous,.not_visible{color:#999}.sec{color:#888;margin:8px 0 2px;font-weight:600}
 button{background:#333;color:#eee;border:1px solid #555;border-radius:4px;padding:3px 7px;cursor:pointer}
 kbd{background:#333;border-radius:3px;padding:0 4px}
</style></head><body>
<div id="side">
 <div><button onclick="prevClip()">◀ p</button> <select id="clipsel" onchange="loadClip(this.value)"></select> <button onclick="nextClip()">n ▶</button></div>
 <div style="margin:6px 0"><button onclick="save()">Save (s)</button> <span id="dirty"></span></div>
 <div style="font-size:11px;color:#999">click place armed · drag move · wheel zoom · right-drag pan<br>
  <kbd>a</kbd>accept <kbd>r</kbd>reject <kbd>b</kbd>ambiguous <kbd>v</kbd>not-visible <kbd>d</kbd>clear <kbd>[</kbd><kbd>]</kbd>arm <kbd>f</kbd>fit</div>
 <div id="list"></div>
</div>
<div id="main"><div id="hud"></div><canvas id="cv"></canvas></div>
<script>
let clips=[], clip=null, obs={}, meta={}, imgW=0,imgH=0, img=new Image();
let view={z:1,ox:0,oy:0}, armIdx=0, sel=null, dirty=false, dragging=false, panning=false, panA=null;
const cv=document.getElementById('cv'), ctx=cv.getContext('2d');
const COL={verified:'#5f5',suggested:'#fc6',ambiguous:'#999',not_visible:'#777',rejected:null};
function resize(){cv.width=cv.clientWidth;cv.height=cv.clientHeight;draw();}
window.addEventListener('resize',resize);
async function init(){clips=await (await fetch('/api/clips')).json();
 const s=document.getElementById('clipsel');s.innerHTML=clips.map(c=>`<option>${c}</option>`).join('');
 meta=await (await fetch('/api/geometry')).json(); loadClip(clips[0]);}
async function loadClip(c){if(dirty&&!confirm('Discard unsaved changes?'))return;
 clip=c;document.getElementById('clipsel').value=c;
 const d=await (await fetch('/api/clip/'+c)).json();obs=d.observations;imgW=d.w;imgH=d.h;
 img.onload=()=>{fit();renderList();};img.src='/plate/'+c+'?t='+Date.now();sel=null;dirty=false;}
function fit(){const z=Math.min(cv.width/imgW,cv.height/imgH);view={z:z,ox:0,oy:0};draw();}
function toImg(sx,sy){return [(sx-view.ox)/view.z,(sy-view.oy)/view.z];}
function toScr(ix,iy){return [ix*view.z+view.ox,iy*view.z+view.oy];}
function draw(){ctx.setTransform(1,0,0,1,0,0);ctx.clearRect(0,0,cv.width,cv.height);
 ctx.drawImage(img,view.ox,view.oy,imgW*view.z,imgH*view.z);
 for(const n in obs){const o=obs[n];if(o.x==null||o.status=='rejected')continue;
  const c=COL[o.status]||'#5f5';const [sx,sy]=toScr(o.x,o.y);
  ctx.beginPath();ctx.arc(sx,sy,n==sel?7:4,0,7);ctx.strokeStyle=c;ctx.fillStyle=c;
  if(n==sel){ctx.lineWidth=2;ctx.stroke();}else ctx.fill();
  ctx.fillStyle=c;ctx.font='11px system-ui';ctx.fillText(n,sx+6,sy-6);}
 hud();}
function hud(){let v=0,sg=0;for(const n in obs){if(obs[n].status=='verified')v++;if(obs[n].status=='suggested')sg++;}
 document.getElementById('hud').textContent=`${clip}  arm:${meta.arm_order[armIdx]}  sel:${sel||'-'}  verified:${v} sugg:${sg}  ${dirty?'*UNSAVED':''}`;
 document.getElementById('dirty').textContent=dirty?'● unsaved':'';}
function renderList(){const el=document.getElementById('list');let h='';let sec='';
 meta.arm_order.forEach((n,i)=>{const grp=n.split('_').slice(0,-1).join('_')||n;
  if(grp!=sec){sec=grp;h+=`<div class="sec">${sec}${meta.anchors.includes(n)?' (anchor)':' (check)'}</div>`;}
  const o=obs[n]||{};const cls=o.status||'';
  h+=`<div class="lm ${i==armIdx?'armed':''} ${cls}" onclick="armName('${n}')"><span>${n}</span><span>${o.status?o.status[0]:''}</span></div>`;});
 el.innerHTML=h;}
function armName(n){armIdx=meta.arm_order.indexOf(n);draw();renderList();}
function nearest(ix,iy){let best=null,bd=14/view.z;for(const n in obs){const o=obs[n];if(o.x==null||o.status=='rejected')continue;
 const d=Math.hypot(o.x-ix,o.y-iy);if(d<bd){best=n;bd=d;}}return best;}
cv.addEventListener('mousedown',e=>{if(e.button==2){panning=true;panA=[e.offsetX,e.offsetY,view.ox,view.oy];return;}
 const [ix,iy]=toImg(e.offsetX,e.offsetY);const hit=nearest(ix,iy);
 if(hit){sel=hit;dragging=true;}else{const n=meta.arm_order[armIdx];obs[n]={x:ix,y:iy,status:'verified',source:'manual'};sel=n;dirty=true;}
 draw();renderList();});
cv.addEventListener('mousemove',e=>{if(panning&&panA){view.ox=panA[2]+(e.offsetX-panA[0]);view.oy=panA[3]+(e.offsetY-panA[1]);draw();return;}
 if(dragging&&sel){const [ix,iy]=toImg(e.offsetX,e.offsetY);obs[sel].x=ix;obs[sel].y=iy;obs[sel].status='verified';obs[sel].source='manual-adjusted';dirty=true;draw();}});
window.addEventListener('mouseup',()=>{dragging=false;panning=false;});
cv.addEventListener('contextmenu',e=>e.preventDefault());
cv.addEventListener('wheel',e=>{e.preventDefault();const [ix,iy]=toImg(e.offsetX,e.offsetY);
 view.z*=(e.deltaY<0?1.2:1/1.2);view.ox=e.offsetX-ix*view.z;view.oy=e.offsetY-iy*view.z;draw();},{passive:false});
function setStatus(st){if(!sel)return;obs[sel].status=st;dirty=true;draw();renderList();}
document.addEventListener('keydown',e=>{const k=e.key;
 if(k=='[')armIdx=(armIdx-1+meta.arm_order.length)%meta.arm_order.length;
 else if(k==']')armIdx=(armIdx+1)%meta.arm_order.length;
 else if(k=='a'&&sel){obs[sel].status='verified';dirty=true;}
 else if(k=='r'&&sel)setStatus('rejected');
 else if(k=='b'&&sel)setStatus('ambiguous');
 else if(k=='v'&&sel)setStatus('not_visible');
 else if((k=='d'||k=='Delete'||k=='Backspace')&&sel){delete obs[sel];sel=null;dirty=true;}
 else if(k=='f')fit();
 else if(k=='s'){e.preventDefault();save();}
 else if(k=='n')nextClip();else if(k=='p')prevClip();else return;
 draw();renderList();});
function nextClip(){loadClip(clips[(clips.indexOf(clip)+1)%clips.length]);}
function prevClip(){loadClip(clips[(clips.indexOf(clip)-1+clips.length)%clips.length]);}
async function save(){await fetch('/api/clip/'+clip,{method:'POST',headers:{'Content-Type':'application/json'},
 body:JSON.stringify({clip_id:clip,image_size:[imgW,imgH],observations:obs})});dirty=false;hud();
 document.getElementById('dirty').textContent='saved ✓';}
init();
</script></body></html>"""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, body, ctype="application/json"):
        if isinstance(body, str):
            body = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/":
            return self._send(200, PAGE, "text/html")
        if path == "/api/clips":
            return self._send(200, json.dumps(_clip_ids()))
        if path == "/api/geometry":
            return self._send(200, json.dumps(_geometry_meta()))
        if path.startswith("/api/clip/"):
            clip = path[len("/api/clip/"):]
            ls, (w, h) = _load_clip(clip)
            obs = {n: {"x": o.x, "y": o.y, "status": o.status, "source": o.source, "confidence": o.confidence}
                   for n, o in ls.observations.items()}
            return self._send(200, json.dumps({"observations": obs, "w": w, "h": h}))
        if path.startswith("/plate/"):
            clip = path[len("/plate/"):]
            with open(_plate_path(clip), "rb") as fh:
                return self._send(200, fh.read(), "image/png")
        return self._send(404, "{}")

    def do_POST(self):
        if self.path.startswith("/api/clip/"):
            n = int(self.headers.get("Content-Length", 0))
            d = json.loads(self.rfile.read(n) or b"{}")
            ls = LandmarkSet.from_dict(d)
            ls.to_json(_json_path(ls.clip_id))
            print(f"saved {ls.clip_id}: {ls.verified_count()} verified, {ls.suggested_count()} suggested")
            return self._send(200, json.dumps({"ok": True, "verified": ls.verified_count()}))
        return self._send(404, "{}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--autofill", action="store_true")
    a = ap.parse_args()
    STATE["dir"] = a.dir
    STATE["autofill"] = a.autofill
    srv = ThreadingHTTPServer(("127.0.0.1", a.port), Handler)
    print(f"LaneSight labeler → open http://localhost:{a.port}/ in Chrome")
    print(f"serving plates from {a.dir}  (autofill={'on' if a.autofill else 'off'})  Ctrl-C to stop")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped")


if __name__ == "__main__":
    main()
