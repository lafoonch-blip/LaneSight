"""Foot-crop refinement experiment: re-run pose on an upscaled person-bbox crop (original full-res frame) to
raise foot-landmark confidence, map feet back, re-score per-foot stance plants. Report conf before/after + ±3f.
Approach-window frames only (runtime). Hold out IMG_8980 (reported separately)."""
import json, os, sys
import numpy as np, cv2
import mediapipe as mp
from mediapipe.tasks.python import vision, BaseOptions
from lanesight_core.form import pose as P

LAB=json.load(open(os.path.join(os.path.dirname(P.__file__),'..','..','validation','form_steps_labels.json')))['clips']
SUBS=['','Form Videos','11:1 Shots']
def find(c):
    for s in SUBS:
        for e in ('MOV','mov'):
            q=os.path.expanduser(f'~/LaneSightData/training_videos/{s}/{c}.{e}')
            if os.path.exists(q): return q
TRAIN=['IMG_8824','IMG_8825','IMG_8826','IMG_8846','IMG_8847','IMG_8848']

FOOT=[P.L_ANKLE,P.R_ANKLE,P.L_HEEL,P.R_HEEL,P.L_FOOT,P.R_FOOT]
_img_lm=None
def img_landmarker():
    global _img_lm
    if _img_lm is None:
        _img_lm=vision.PoseLandmarker.create_from_options(vision.PoseLandmarkerOptions(
            base_options=BaseOptions(model_asset_path=P.POSE_MODEL_PATH),
            running_mode=vision.RunningMode.IMAGE, num_poses=1,
            min_pose_detection_confidence=0.3, min_tracking_confidence=0.3))
    return _img_lm

def person_bbox(lmrow, pad=0.18):
    v=lmrow[:,3]>0.3
    if v.sum()<6: return None
    xs=lmrow[v,0]; ys=lmrow[v,1]
    x0,x1=xs.min(),xs.max(); y0,y1=ys.min(),ys.max()
    w=x1-x0; h=y1-y0
    x0-=pad*w; x1+=pad*w; y0-=pad*h; y1+=pad*h
    return max(0,x0),max(0,y0),min(1,x1),min(1,y1)

def refine_window(video, t, lms, win):
    """Re-run pose on an upscaled person-bbox crop for frames in win; return dict frame_idx->refined 33x5 (feet
    mapped to full-frame normalized coords). Only foot channels are trusted from the refined pass."""
    pts=P.frame_times(video)
    cap=cv2.VideoCapture(video)
    if hasattr(cv2,"CAP_PROP_ORIENTATION_AUTO"): cap.set(cv2.CAP_PROP_ORIENTATION_AUTO,1)
    lm=img_landmarker()
    out={}
    i=0
    while True:
        ok,img=cap.read()
        if not ok: break
        tt=float(pts[i]) if i<len(pts) else i/30.0
        if win[0]<=tt<=win[1]:
            H,W=img.shape[:2]
            bb=person_bbox(lms[i]) if i<len(lms) else None
            if bb is not None:
                x0,y0,x1,y1=bb
                cx0,cy0,cx1,cy1=int(x0*W),int(y0*H),int(x1*W),int(y1*H)
                if cx1-cx0>10 and cy1-cy0>10:
                    crop=img[cy0:cy1,cx0:cx1]
                    scale=max(1.0, 384.0/max(crop.shape[0],crop.shape[1]))
                    crop2=cv2.resize(crop,None,fx=scale,fy=scale,interpolation=cv2.INTER_CUBIC)
                    rgb=cv2.cvtColor(crop2,cv2.COLOR_BGR2RGB)
                    res=lm.detect(mp.Image(image_format=mp.ImageFormat.SRGB,data=rgb))
                    if res.pose_landmarks:
                        L=res.pose_landmarks[0]
                        row=np.array([[p.x,p.y,p.z,p.visibility,p.presence] for p in L],np.float32)
                        # map crop-normalized -> full-frame normalized
                        bw=(x1-x0); bh=(y1-y0)
                        row[:,0]=x0+row[:,0]*bw; row[:,1]=y0+row[:,1]*bh
                        out[i]=row
        if tt>win[1]: break
        i+=1
    cap.release()
    return out

def forward(xp,yp,tt):
    def fill(a):
        g=~np.isnan(a); return np.interp(tt,tt[g],a[g]) if g.any() else np.zeros_like(tt)
    x=fill(xp); y=fill(yp)
    f=x if abs(x[-1]-x[0])>abs(y[-1]-y[0]) else y
    if f[-1]<f[0]: f=-f
    return P._smooth(f,5)

def stance_onsets(f,tt,vthr=0.15,ms=0.10,mstr=0.03):
    v=np.gradient(f,tt); dt=np.median(np.diff(tt)); need=max(1,int(ms/dt))
    holds=[]; i=0; n=len(tt)
    while i<n:
        if v[i]<vthr:
            j=i
            while j<n and v[j]<vthr: j+=1
            if (j-i)>=need: holds.append((i,j))
            i=j
        else: i+=1
    ons=[]; last=None
    for a,b in holds:
        fh=np.median(f[a:b])
        if last is None or (fh-last)>=mstr: ons.append(a); last=fh
    return ons

def plants_from_feet(t,Lx,Ly,Rx,Ry,Rs,Ls,start,end):
    m=(t>=start)&(t<=end); tt=t[m]
    rp=[tt[i] for i in stance_onsets(forward(Rx[m],Ry[m],tt),tt)]
    lp=[tt[i] for i in stance_onsets(forward(Lx[m],Ly[m],tt),tt)]
    allp=sorted(rp+lp); merged=[]
    for x in allp:
        if merged and x-merged[-1]<0.14: continue
        merged.append(x)
    return merged

def score_plants(merged,vis,fps,tol):
    used=set(); errs=[]
    for gt in vis:
        best=None
        for i,dt in enumerate(merged):
            if i in used: continue
            fe=(dt-gt)*fps
            if best is None or abs(fe)<abs(best[1]): best=(i,fe)
        if best and abs(best[1])<=9: used.add(best[0]); errs.append(round(best[1],1))
        else: errs.append(None)
    within=sum(1 for e in errs if e is not None and abs(e)<=tol)
    return within,errs

def run(cid):
    lab=LAB[cid]; fps=lab['fps']; p=find(cid)
    vis=[lab[f'step{k}_s'] for k in range(1,7) if lab.get(f'step{k}_s') is not None]
    t,lms=P.extract_landmarks(p,log=lambda*a:None)
    Rx,Ry=P._point(lms,P.R_FOOT_PTS,0),P._point(lms,P.R_FOOT_PTS,1)
    Lx,Ly=P._point(lms,P.L_FOOT_PTS,0),P._point(lms,P.L_FOOT_PTS,1)
    Rs,Ls=P._speed(Rx,Ry,t),P._speed(Lx,Ly,t)
    b0=P._find_delivery(t,lms,Rs,Ls)[0][0]+0.4
    start=P._setup_hold_end(t,Rs,Ls,b0)
    _,sf=P._slide_foot(t,Rs,Ls,start,start+2.5,'right')
    ss=P._slide_stop(t,sf,(vis[-1]),start+3.0)
    end=(ss or vis[-1])+0.1
    win=(start-0.1,end+0.1)
    # BEFORE confidence (full-frame foot vis in window)
    mm=(t>=win[0])&(t<=win[1])
    conf_before=float(np.nanmean(lms[mm][:,FOOT,3]))
    merged_b=plants_from_feet(t,Lx,Ly,Rx,Ry,Rs,Ls,start,end)
    w3_b,errs_b=score_plants(merged_b,vis,fps,3)
    # REFINE
    ref=refine_window(p,t,lms,win)
    lms2=lms.copy()
    for i,row in ref.items():
        for j in FOOT:                       # only replace foot channels where refined vis is higher
            if row[j,3]>=lms2[i,j,3]:
                lms2[i,j]=row[j]
    conf_after=float(np.nanmean(lms2[mm][:,FOOT,3]))
    Rx2,Ry2=P._point(lms2,P.R_FOOT_PTS,0),P._point(lms2,P.R_FOOT_PTS,1)
    Lx2,Ly2=P._point(lms2,P.L_FOOT_PTS,0),P._point(lms2,P.L_FOOT_PTS,1)
    Rs2,Ls2=P._speed(Rx2,Ry2,t),P._speed(Lx2,Ly2,t)
    merged_a=plants_from_feet(t,Lx2,Ly2,Rx2,Ry2,Rs2,Ls2,start,end)
    w3_a,errs_a=score_plants(merged_a,vis,fps,3)
    ho=' HELDOUT' if cid=='IMG_8980' else ''
    print(f'{cid}{ho} vis={len(vis)} | conf {conf_before:.2f}->{conf_after:.2f} | '
          f'±3f BEFORE {w3_b}/{len(vis)} (det{len(merged_b)}) AFTER {w3_a}/{len(vis)} (det{len(merged_a)}) '
          f'| errsA={errs_a}')

for cid in (sys.argv[1:] or TRAIN+['IMG_8980']):
    run(cid)
