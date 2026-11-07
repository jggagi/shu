#!/usr/bin/env python3
"""Compile two custom-control motion variants without changing the original catalog.

python3 tools/build_martial_control_variants.py --report .local/qa/control-batch.json
Use --check-only to validate the complete authoring batch before production.
Fingerprints contain recipe/profile/source/tool bytes, never consumer runtime or
provenance documents. The original six-move catalog and source models are read-only.
"""
from __future__ import annotations
import argparse, copy, hashlib, importlib.util, json, math, os, re, subprocess, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('workshop_batch',ROOT/'tools/build_martial_workshop.py');base=importlib.util.module_from_spec(spec);spec.loader.exec_module(base)
COMPILER=ROOT/'tools/hero_lookdev/build_martial_control_motions.py'
def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def write(path,value):
 path=Path(path);path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(value,ensure_ascii=False,indent=2,allow_nan=False)+'\n')
def hash_obj(value):return hashlib.sha256(json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':'),allow_nan=False).encode()).hexdigest()
def validate_footwork(path,recipe):
 parameters=recipe.get('footwork')
 if parameters is None:return {}
 def number(value):return type(value) in {int,float} and math.isfinite(value)
 if not isinstance(parameters,dict) or set(parameters)!={'template','active_side','distance_m','lift_m'} or parameters['active_side'] not in {'L','R'}:raise ValueError('Invalid footwork parameters')
 if not isinstance(parameters['template'],str):raise ValueError('Template name must be a string')
 for name,bounds in [('distance_m',(.05,.28)),('lift_m',(.02,.08))]:
  if not number(parameters[name]) or not bounds[0]<=parameters[name]<=bounds[1]:raise ValueError('Footwork '+name+' outside supported short-step bounds')
 template_path=(path.parent/parameters['template']).resolve()
 if template_path.parent!=path.parent.resolve() or template_path.name!='step_plant_return.template.json':raise ValueError('Footwork must use the local step/plant/return template')
 template_bytes=template_path.read_bytes();template=json.loads(template_bytes)
 if template.get('schema_version')!=1 or template.get('kind')!='footwork_template' or template.get('id')!='step_plant_return':raise ValueError('Invalid footwork template identity')
 keys=template['keys'];last=-1.
 if not isinstance(keys,list) or len(keys)<4:raise ValueError('Footwork needs ordered normalized keys')
 for key in keys:
  if not isinstance(key,dict) or set(key)!={'t','advance','lift'} or not all(number(v) for v in key.values()) or not last<key['t']<=1 or not 0<=key['advance']<=1 or not 0<=key['lift']<=1:raise ValueError('Invalid normalized footwork key')
  last=key['t']
 if keys[0]!={'t':0,'advance':0,'lift':0} or keys[-1]!={'t':1,'advance':0,'lift':0} or keys[1]['advance'] or keys[1]['lift'] or keys[-2]['advance'] or keys[-2]['lift']:raise ValueError('Footwork requires stationary neutral boundary intervals')
 phases=template['phases'];last=0
 if not isinstance(phases,list) or not phases:raise ValueError('Footwork needs ordered phases')
 for phase in phases:
  if not isinstance(phase,dict) or set(phase)!={'from','to','label'} or not all(number(phase[k]) for k in ['from','to']) or phase['from']!=last or not last<phase['to']<=1 or not isinstance(phase['label'],str) or not phase['label']:raise ValueError('Invalid normalized footwork phases')
  last=phase['to']
 if last!=1:raise ValueError('Footwork phases must cover0..1')
 planted=template['planted_interval']
 if not isinstance(planted,list) or len(planted)!=2 or not all(number(v) for v in planted):raise ValueError('Invalid planted interval')
 plant,release=planted
 if not 0<plant<release<1 or not any(k['t']==plant and k['advance']==1 and k['lift']==0 for k in keys) or not any(k['t']==release and k['advance']==1 and k['lift']==0 for k in keys) or any(k['advance']!=1 or k['lift'] for k in keys if plant<=k['t']<=release):raise ValueError('Footwork requires an exact planted plateau')
 return {str(template_path.relative_to(ROOT)):hashlib.sha256(template_bytes).hexdigest()}
def validate(recipe,profiles,moves):
 if recipe.get('schema_version')!=1 or recipe.get('variant_id')!='enhanced' or recipe['move_id'] not in moves:raise ValueError('Invalid variant schema/id')
 move=moves[recipe['move_id']]
 if recipe['profile']!=move['profile'] or recipe['category']!=move['category']:raise ValueError('Variant profile/category differs')
 if not math.isfinite(recipe['seconds']) or recipe['seconds']!=move['animation']['source_seconds']:raise ValueError('Variant duration must equal original')
 last_phase=0
 for phase in recipe['phases']:
  if not all(isinstance(phase[k],(float,int)) and math.isfinite(phase[k]) for k in ['from','to']) or phase['from']!=last_phase or not phase['from']<phase['to']<=recipe['seconds'] or not phase['label']:raise ValueError('Invalid phase interval')
  last_phase=phase['to']
 if last_phase!=recipe['seconds']:raise ValueError('Phases must span the complete clip')
 keys=recipe['keys']
 if keys[0]['t']!=0 or keys[-1]['t']!=recipe['seconds']:raise ValueError('Control keys must span source clip')
 last=-1
 for key in keys:
  if not last<key['t']<=recipe['seconds']:raise ValueError('Nonmonotonic control time')
  last=key['t']
  for field in ['hip_yaw','spine_yaw','chest_yaw','lean','gaze_yaw','palm_yaw']:
   if not math.isfinite(key[field]) or abs(key[field])>60:raise ValueError('Unsafe torso/hand control')
  for field in ['shift','elbow_L','elbow_R']:base.vector(key[field],field)
  if abs(key['shift'][2])>.15 or abs(key['shift'][1])>.15:raise ValueError('COG control exceeds conservative .15m bounds')
  for field in ['left','right','right_direction']:
   if key[field]!='neutral':
    v=base.vector(key[field],field)
    if field=='right_direction' and sum(x*x for x in v)<1e-8:raise ValueError('Sword direction cannot be zero')
  if not 0<=key['palm_open']<=1:raise ValueError('Palm open outside0..1')
 for key in [keys[0],keys[-1]]:
  if any(key[field]!='neutral' for field in ['left','right','right_direction']) or key['shift']!=[0,0,0] or any(key[x] for x in ['hip_yaw','spine_yaw','chest_yaw','lean','gaze_yaw','palm_open','palm_yaw']):raise ValueError('Exact neutral boundaries required')
 return {ref:sha(base.res_file(ref)) for ref in sorted(set(base.resource_refs(profiles[move['profile']]))|set(base.resource_refs(move)))}
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--recipes-dir',type=Path,default=ROOT/'assets/data/martial_workshop/control_rig');p.add_argument('--output',type=Path,default=ROOT/'assets/art/martial_workshop/control_rig');p.add_argument('--sources-root',type=Path,default=ROOT/'.local/sources/martial-control-rig');p.add_argument('--variants-output',type=Path);p.add_argument('--edited-blend',action='append',default=[],metavar='MOVE_ID=PATH');p.add_argument('--blender',default='/usr/bin/blender');p.add_argument('--godot',default='/opt/agent-creator/godot/bin/godot');p.add_argument('--log-root',type=Path,default=ROOT/'.local/qa/martial-control-rig/motion');p.add_argument('--check-only',action='store_true');p.add_argument('--report',type=Path);a=p.parse_args()
 a.recipes_dir=a.recipes_dir.resolve();a.output=a.output.resolve();a.sources_root=a.sources_root.resolve();a.log_root=a.log_root.resolve()
 try:
  catalog_path=ROOT/'assets/data/martial_workshop/catalog.json';catalog_sha=sha(catalog_path);catalog=json.loads(catalog_path.read_text());profiles=catalog['profiles'];profile_path=ROOT/'assets/data/martial_workshop/profiles.json'
  if json.loads(profile_path.read_text())['profiles']!=profiles:raise ValueError('Compiler profiles.json differs from catalog profiles')
  for name,profile in profiles.items():base.validate_profile(name,profile)
  edited={}
  for entry in a.edited_blend:
   move_id,sep,value=entry.partition('=')
   if not sep or move_id in edited or not Path(value).is_file():raise ValueError('Expected unique --edited-blend MOVE_ID=existing-copy.blend')
   edited[move_id]=Path(value).resolve()
  if edited and a.variants_output is None:raise ValueError('Edited production requires explicit --variants-output, preserving the default approved batch')
  a.variants_output=a.variants_output or ROOT/'assets/data/martial_workshop/control_variants.json'
  moves={m['id']:m for m in catalog['moves']};recipes=[];seen=set()
  for path in sorted(a.recipes_dir.glob('*.json')):
   recipe=json.loads(path.read_text())
   if recipe.get('kind')=='footwork_template':
    if path.name!='step_plant_return.template.json':raise ValueError('Unexpected template file')
    continue
   inputs=validate(recipe,profiles,moves);inputs.update(validate_footwork(path,recipe));inputs['assets/data/martial_workshop/profiles.json']=sha(profile_path)
   if recipe['move_id'] in edited:inputs['edited_blend:'+recipe['move_id']]=sha(edited[recipe['move_id']])
   if recipe['move_id'] in seen:raise ValueError('Duplicate variant')
   seen.add(recipe['move_id']);recipes.append((path,recipe,inputs))
  if not recipes:raise ValueError('Empty control batch')
  if set(edited)-seen:raise ValueError('Edited source move is absent from this batch')
  report={'schema_version':1,'ok':True,'check_only':a.check_only,'validated':len(recipes),'jobs':[]}
  if a.check_only:
   if a.report:write(a.report,report)
   print(json.dumps(report));return
  for executable in [a.blender,a.godot]:
   if not Path(executable).is_file():raise ValueError('Missing executable '+executable)
  tool_paths=[Path(__file__),COMPILER,ROOT/'tools/build_martial_workshop.py',ROOT/'tools/hero_lookdev/build_ambush_martial_clips.py',ROOT/'tools/hero_lookdev/build_ambush_palm_clips.py']
  tools={str(t.relative_to(ROOT)):sha(t) for t in tool_paths};tools.update(blender_binary_sha256=sha(a.blender),godot_binary_sha256=sha(a.godot))
  variants=[]
  for path,recipe,inputs in recipes:
   move=copy.deepcopy(moves[recipe['move_id']]);fingerprint=hash_obj({'recipe':recipe,'profile':profiles[recipe['profile']],'reference_move':{k:move[k] for k in ['id','animation','timing','visual','audio','camera']},'inputs':inputs,'tools':tools});job=a.output/recipe['move_id']/fingerprint[:16];asset=job/'motion.glb';manifest=job/'manifest.json';cached=False
   if manifest.is_file():
    old=json.loads(manifest.read_text());cached=old.get('inputs')==inputs and old.get('tools')==tools and all(Path(out).is_file() and sha(out)==value for out,value in old.get('output_files',{}).items())
   if cached:variant=old['resolved_variant'];status='cache_hit'
   else:
    job.mkdir(parents=True,exist_ok=True);blend=a.sources_root/recipe['move_id']/fingerprint[:16]/'controls.blend';source_report=job/'source-motion.json';log_dir=a.log_root/recipe['move_id']/fingerprint[:16];log_dir.mkdir(parents=True,exist_ok=True)
    env=dict(os.environ);ocio=ROOT/'.local/qa/tinglan-character/ocio-compat/config.ocio'
    if ocio.is_file():env['OCIO']=str(ocio)
    cmd=[a.blender,'--disable-autoexec','--background','--python-exit-code','1','--python',str(COMPILER),'--','--recipe',str(path),'--profiles',str(ROOT/'assets/data/martial_workshop/profiles.json'),'--root',str(ROOT),'--out',str(asset),'--blend',str(blend),'--report',str(source_report)]
    if recipe.get('footwork'):
     template_key=str((path.parent/recipe['footwork']['template']).resolve().relative_to(ROOT));cmd.extend(['--expected-template-sha256',inputs[template_key]])
    if recipe['move_id'] in edited:cmd.extend(['--edited-blend',str(edited[recipe['move_id']])])
    result=subprocess.run(cmd,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,env=env,timeout=600);(log_dir/'blender.log').write_text(result.stdout)
    if result.returncode:raise RuntimeError('Blender failed for '+recipe['move_id']+': '+result.stdout[-3500:])
    source_data=json.loads(source_report.read_text())
    if not source_data['all_pass']:raise RuntimeError('Source control invariants failed')
    resource='res://'+asset.relative_to(ROOT).as_posix();base.import_profile(asset,resource,a.godot,log_dir/'godot-import.log')
    original_asset=move['animation']['asset'];move['animation'].update(asset=resource,clip=recipe['clip'],sha256=sha(asset));move['preview_only']=True;move['combat_skill']='';move['description']=recipe['description'];move['resource_sha256'][resource]=sha(asset);move.pop('resource_hash',None);move['resource_hash']=hash_obj(move)
    variant={'move_id':move['id'],'variant_id':'enhanced','variant_label':recipe['variant_label'],'description':recipe['description'],'move':move}
    output_files={str(out):sha(out) for out in [asset,asset.with_suffix('.glb.import'),source_report,blend]}
    write(manifest,{'schema_version':1,'fingerprint':fingerprint,'inputs':inputs,'tools':tools,'recipe_sha256':sha(path),'output_files':output_files,'resolved_variant':variant,'provenance':{'author':'Codex for Shu; original custom-control choreography','license':profiles[recipe['profile']]['source_license'],'cloud_calls':0,'paid_calls':0,'installs':0,'runtime_files_in_fingerprint':False}});status='generated'
   variants.append(variant);record={'id':recipe['move_id'],'status':status,'fingerprint':fingerprint,'asset':variant['move']['animation']['asset'],'sha256':variant['move']['animation']['sha256'],'manifest':str(manifest)};report['jobs'].append(record);print('CONTROL_JOB '+json.dumps(record),flush=True)
  if sha(catalog_path)!=catalog_sha:raise RuntimeError('Original catalog changed during production')
  for profile in profiles.values():
   if sha(base.res_file(profile['source_asset']))!=profile['source_sha256']:raise RuntimeError('Original model changed')
  write(a.variants_output,{'schema_version':1,'base_catalog_sha256':catalog_sha,'variants':variants});report.update(base_catalog_sha256=catalog_sha,variants_path=str(a.variants_output),variants_sha256=sha(a.variants_output),cache_hits=sum(x['status']=='cache_hit' for x in report['jobs']),generated=sum(x['status']=='generated' for x in report['jobs']))
  if a.report:write(a.report,report)
  print('CONTROL_BATCH '+json.dumps(report),flush=True)
 except (ValueError,KeyError,TypeError,OSError,RuntimeError,subprocess.TimeoutExpired) as error:
  report={'schema_version':1,'ok':False,'error':str(error),'check_only':a.check_only}
  if a.report:write(a.report,report)
  print(json.dumps(report),file=sys.stderr);sys.exit(1)
if __name__=='__main__':main()
