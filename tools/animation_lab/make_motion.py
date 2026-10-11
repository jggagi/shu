"""Original, zero-cost full-body motion study; same poses drive all candidates.
Coordinates: metres; X forward, Y lateral, Z up. No gameplay state.
"""
import json, math
from pathlib import Path
FPS=30
DURATION=4.0
BONES=[
 ('hips','hip','chest',None),('chest','chest','neck','hips'),('head','neck','crown','chest'),
 ('upper_R','shoulder_R','elbow_R','chest'),('fore_R','elbow_R','hand_R','upper_R'),
 ('upper_L','shoulder_L','elbow_L','chest'),('fore_L','elbow_L','hand_L','upper_L'),
 ('thigh_R','hip_R','knee_R','hips'),('shin_R','knee_R','ankle_R','thigh_R'),('foot_R','ankle_R','toe_R','shin_R'),
 ('thigh_L','hip_L','knee_L','hips'),('shin_L','knee_L','ankle_L','thigh_L'),('foot_L','ankle_L','toe_L','shin_L'),
 ('weapon','hand_R','tip','fore_R')]
def add(a,b):return [a[i]+b[i] for i in range(3)]
def sub(a,b):return [a[i]-b[i] for i in range(3)]
def mul(a,n):return [x*n for x in a]
def dot(a,b):return sum(x*y for x,y in zip(a,b))
def length(a):return math.sqrt(dot(a,a))
def normal(a):return mul(a,1/max(1e-8,length(a)))
def yaw(a,degrees):
 c,s=math.cos(math.radians(degrees)),math.sin(math.radians(degrees))
 return [a[0]*c-a[1]*s,a[0]*s+a[1]*c,a[2]]
def ik(start,end,a,b,pole):
 delta=sub(end,start); d=min(a+b-.0001,max(abs(a-b)+.0001,length(delta))); axis=normal(delta)
 end=add(start,mul(axis,d))
 projected=sub(pole,mul(axis,dot(pole,axis)))
 if length(projected)<.001:projected=[0,1,0]
 side=normal(projected); x=(a*a-b*b+d*d)/(2*d); h=math.sqrt(max(0,a*a-x*x))
 return add(start,add(mul(axis,x),mul(side,h))),end
READY={'hx':0.,'hz':.98,'yaw':0.,'lean':.025,'R':[.39,-.22,1.40],'L':[.16,.24,1.38],'dir':[.76,0,.65],'step':0.,'lift':0.}
def pose(**kw):p=dict(READY);p.update(kw);return p
KEYS={
 'thrust':[(0,pose()),(.45,pose(hx=-.05,lean=-.02,R=[.12,-.22,1.45],dir=[1,0,.05])),(.85,pose(hx=-.05,lean=-.02,R=[.12,-.22,1.45],dir=[1,0,.05])),
 (1.02,pose(hx=.02,hz=.96,step=.45,lift=.10,R=[.35,-.22,1.42],dir=[1,0,.05])),(1.38,pose(hx=.24,hz=.90,lean=.10,step=1.,R=[.91,-.22,1.43],L=[.35,.24,1.42],dir=[1,0,.035])),
 (1.65,pose(hx=.24,hz=.90,lean=.10,step=1.,R=[.91,-.22,1.43],L=[.35,.24,1.42],dir=[1,0,.035])),(2.2,pose(hx=.16,hz=.94,step=1.,R=[.43,-.22,1.42],dir=[.90,0,.43])),(2.7,pose(hx=.03,step=.50,lift=.08)),(3.2,pose()),(4.,pose())],
 'cut':[(0,pose()),(.48,pose(hx=-.035,yaw=-18,lean=-.035,R=[.05,-.22,1.94],L=[-.18,.25,1.49],dir=[-.15,0,.99])),(.95,pose(hx=-.035,yaw=-18,lean=-.035,R=[.05,-.22,1.94],L=[-.18,.25,1.49],dir=[-.15,0,.99])),
 (1.20,pose(hx=.08,hz=.94,yaw=12,lean=.07,R=[.43,-.22,1.80],dir=[.98,0,.20])),(1.48,pose(hx=.16,hz=.90,yaw=68,lean=.08,R=[.67,-.22,1.27],L=[-.08,.25,1.45],dir=[.72,0,-.70])),(1.82,pose(hx=.14,hz=.92,yaw=74,lean=.05,R=[.62,-.22,1.22],dir=[.65,0,-.76])),
 (2.30,pose(yaw=42,R=[.35,-.22,1.39],dir=[.95,0,.30])),(3.15,pose()),(4.,pose())],
 'staff':[(0,pose(R=[.25,-.08,1.40],dir=[.99,0,.12])),(.45,pose(hx=-.04,yaw=-20,lean=-.04,R=[.07,-.08,1.42],dir=[.96,0,.28])),(.85,pose(hx=-.04,yaw=-20,lean=-.04,R=[.07,-.08,1.42],dir=[.96,0,.28])),
 (1.0,pose(hx=.01,yaw=-8,step=.45,lift=.10,R=[.28,-.08,1.40],dir=[1,0,0])),(1.4,pose(hx=.22,hz=.91,yaw=28,lean=.08,step=1,R=[.47,-.08,1.43],dir=[1,0,0])),(1.75,pose(hx=.22,hz=.91,yaw=28,lean=.08,step=1,R=[.47,-.08,1.43],dir=[1,0,0])),
 (2.25,pose(hx=.10,yaw=-14,step=1,R=[.20,-.08,1.48],dir=[.86,0,.51])),(2.7,pose(step=.5,lift=.08,R=[.25,-.08,1.40],dir=[.99,0,.12])),(3.2,pose(R=[.25,-.08,1.40],dir=[.99,0,.12])),(4.,pose(R=[.25,-.08,1.40],dir=[.99,0,.12]))]}
def sample(keys,t):
 for (ta,a),(tb,b) in zip(keys,keys[1:]):
  if t<=tb:
   w=max(0.,min(1.,(t-ta)/(tb-ta))); w=w*w*(3-2*w)
   return {k:([a[k][i]*(1-w)+b[k][i]*w for i in range(3)] if isinstance(a[k],list) else a[k]*(1-w)+b[k]*w) for k in a}
 return keys[-1][1]
def joints(p,clip):
 hip=[p['hx'],0,p['hz']]; angle=p['yaw']; chest=add(hip,yaw([p['lean'],0,math.sqrt(.54**2-p['lean']**2)],angle)); neck=add(chest,[0,0,.17]); crown=add(neck,[0,0,.66]); data={'hip':hip,'chest':chest,'neck':neck,'crown':crown}
 # Hands authored in the moving torso's local facing, z supplied in world-height units.
 R=add([p['hx'],0,0],yaw(p['R'],angle)); direction=normal(yaw(p['dir'],angle))
 L=add(R,mul(direction,.34)) if clip=='staff' else add([p['hx'],0,0],yaw(p['L'],angle))
 for side,side_y,target in [('R',-.18,R),('L',.18,L)]:
  shoulder=add(chest,yaw([0,side_y,.03],angle)); pole=yaw([-.36,side_y*2,-.55],angle)
  elbow,hand=ik(shoulder,target,.40,.40,pole)
  data['shoulder_'+side]=shoulder;data['elbow_'+side]=elbow;data['hand_'+side]=hand
  hip_joint=add(hip,yaw([0,side_y*.7,0],angle))
  ankle=[.24+.36*p['step'] if side=='R' else -.24, side_y*.85,.09+(p['lift'] if side=='R' else 0)]
  knee,ankle=ik(hip_joint,ankle,.55,.55,yaw([1,0,-.04],angle))
  data['hip_'+side]=hip_joint;data['knee_'+side]=knee;data['ankle_'+side]=ankle;data['toe_'+side]=add(ankle,yaw([.22,0,-.015],angle))
 # Both staff grips are constrained onto a rigid pole; target is reachable in the authored poses.
 if clip=='staff':
  data['hand_L']=add(data['hand_R'],mul(direction,.34))
  data['elbow_L'],_=ik(data['shoulder_L'],data['hand_L'],.40,.40,yaw([-.36,.40,-.55],angle))
 data['tip']=add(data['hand_R'],mul(direction,1.12 if clip=='staff' else .90)); data['butt']=add(data['hand_R'],mul(direction,-.68 if clip=='staff' else -.14))
 data['yaw']=angle
 return data
# Exact orthographic projection used by the Blender camera; pixel viewport height / ortho scale.
CAMERA=[4.,-7.,3.3];TARGET=[0,0,1.4];ORTHO=4.2
forward=normal(sub(TARGET,CAMERA)); right=normal([forward[1],-forward[0],0]); up=[right[1]*forward[2],-right[0]*forward[2],right[0]*forward[1]-right[1]*forward[0]]
def project(p):return [dot(p,right),-dot(p,up)]
def main():
 frames={clip:[{'at':i/FPS,'joints':joints(sample(keys,i/FPS),clip)} for i in range(int(DURATION*FPS)+1)] for clip,keys in KEYS.items()}
 result={'version':1,'author':'Codex, original motion study','status':'exploration; not final Jiang artwork or verified martial technique','fps':FPS,'duration':DURATION,'camera':{'position':CAMERA,'target':TARGET,'ortho':ORTHO,'right':right,'up':up},'bones':[{'name':n,'head':h,'tail':t,'parent':p} for n,h,t,p in BONES],'clips':frames,'labels':{'thrust':'弓步直刺','cut':'转身斜劈','staff':'双手棍法'}}
 path=Path(__file__).resolve().parents[2]/'assets/data/animation_lab/motion.json';path.write_text(json.dumps(result,separators=(',',':'))+'\n')
 print(f'Original motion: {len(frames)} clips, {sum(len(f) for f in frames.values())} poses -> {path}')
if __name__=='__main__':main()
