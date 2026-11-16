"""Multi-cue step COUNT prototype (cached pose). Compare periodic whole-body cues between setup-hold-end and
slide-stop: hip-y bounce, knee-y bounce, knee forward-swing (thigh), thigh angle. Gate: count==5 on all 7."""
import json, os
import numpy as np
from lanesight_core.form import pose as P
LAB=json.load(open(os.path.join(os.path.dirname(P.__file__),'..','..','validation','form_steps_labels.json')))['clips']
SUBS=['','Form Videos','11:1 Shots']
L_KNEE,R_KNEE=25,26
def find(c):
    for s in SUBS:
        for e in ('MOV','mov'):
            q=os.path.expanduser(f'~/LaneSightData/training_videos/{s}/{c}.{e}')
            if os.path.exists(q): return q
ALL=['IMG_8824','IMG_8825','IMG_8826','IMG_8846','IMG_8847','IMG_8848','IMG_8980']
CACHE={}
def load(c):
    if c in CACHE: return CACHE[c]
    t,lms=P.extract_landmarks(find(c),log=lambda*a:None)
    Rx,Ry=P._point(lms,P.R_FOOT_PTS,0),P._point(lms,P.R_FOOT_PTS,1)
    Lx,Ly=P._point(lms,P.L_FOOT_PTS,0),P._point(lms,P.L_FOOT_PTS,1)
    Rs,Ls=P._speed(Rx,Ry,t),P._speed(Lx,Ly,t)
    b0=P._find_delivery(t,lms,Rs,Ls)[0][0]+0.4
    start=P._setup_hold_end(t,Rs,Ls,b0)
    _,sf=P._slide_foot(t,Rs,Ls,start,start+2.5,'right')
    vis=[LAB[c][f'step{k}_s'] for k in range(1,7) if LAB[c].get(f'step{k}_s')]
    ss=P._slide_stop(t,sf,vis[-1],start+3.0) or vis[-1]
    CACHE[c]=(t,lms,start,ss); return CACHE[c]
def interp(a,tt):
    g=~np.isnan(a); return np.interp(tt,tt[g],a[g]) if g.any() else np.zeros_like(tt)
def detrend(y,tt,win_s=0.7):
    dt=np.median(np.diff(tt)); w=max(3,int(win_s/dt)|1); k=np.ones(w)/w
    return y-np.convolve(np.pad(y,w//2,mode='edge'),k,mode='valid')[:len(y)]
def count_osc(sig,tt,sep_s=0.20,promk=0.3):
    """count local maxima of sig (separated, prominent) — one per oscillation cycle."""
    dt=np.median(np.diff(tt)); w=max(1,int(sep_s/dt)); prom=promk*np.std(sig); pk=[]
    for i in range(len(sig)):
        a,b=max(0,i-w),min(len(sig),i+w+1)
        if sig[i]==sig[a:b].max():
            lm=min(sig[a:i+1].min() if i>a else sig[i], sig[i:b].min() if b>i else sig[i])
            if sig[i]-lm>=prom and (not pk or i-pk[-1]>=w): pk.append(i)
    return len(pk)
print(f'{"clip":11s} hipY kneeY kneeFwd thighAng  (GT 5; *=HELDOUT 8980)')
for c in ALL:
    t,lms,start,ss=load(c); m=(t>=start-0.05)&(t<=ss+0.05); tt=t[m]
    hipy=P._smooth(interp(P._point(lms,(P.L_HIP,P.R_HIP),1)[m],tt),3)
    kny=P._smooth(interp(P._point(lms,(L_KNEE,R_KNEE),1)[m],tt),3)
    # knee forward = dominant horizontal/vertical travel of the mean knee; count its staircase via velocity bursts
    knx=P._smooth(interp(P._point(lms,(L_KNEE,R_KNEE),0)[m],tt),3)
    knfwd = knx if abs(knx[-1]-knx[0])>abs(kny[-1]-kny[0]) else kny
    knfwd = knfwd if knfwd[-1]>knfwd[0] else -knfwd
    # thigh angle (hip->knee vs vertical), per leg, summed abs — each leg swings once/stride; use left+right
    def thigh(hip_i,knee_i):
        hx=interp(lms[m,hip_i,0],tt); hy=interp(lms[m,hip_i,1],tt)
        kx=interp(lms[m,knee_i,0],tt); ky=interp(lms[m,knee_i,1],tt)
        return P._smooth(np.arctan2(kx-hx, ky-hy),3)  # angle from vertical (down)
    tL=thigh(P.L_HIP,L_KNEE); tR=thigh(P.R_HIP,R_KNEE)
    # detrended osc counts (hip high=min image-y -> count -detrend); knee fwd staircase -> count velocity-burst peaks
    nhip=count_osc(-detrend(hipy,tt),tt)
    nkny=count_osc(-detrend(kny,tt),tt)
    # knee forward swings: velocity (one burst per swing). count bursts via local maxima of forward velocity
    v=np.gradient(knfwd,tt); nknf=count_osc(P._smooth(v,3),tt,0.20,0.25)
    # thigh angle: combine both legs (alternate) -> sum of |detrended|; count maxima of -(each) merged
    nthL=count_osc(detrend(tL,tt),tt); nthR=count_osc(detrend(tR,tt),tt)
    star='*' if c=='IMG_8980' else ' '
    print(f'{c}{star:1s} {nhip:4d} {nkny:5d} {nknf:7d} {nthL+nthR:8d}  (thL={nthL} thR={nthR})')
