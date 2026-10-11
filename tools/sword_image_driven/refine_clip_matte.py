"""Offline, local alpha refinement of reviewed backdrop pockets in the approved clip.

Original RGB, source video, poses, anchors, frame layout and timing are retained.
The already-installed general segmentation model is limited by authored regions;
it never replaces the full anime matte (which preserves the thin moving sword).
"""
import argparse, copy, hashlib, importlib.util, json
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import distance_transform_edt, label, maximum_filter, minimum_filter

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def polygon_for_frame(keys, frame):
    indices=sorted(int(k) for k in keys)
    left=max((k for k in indices if k<=frame),default=indices[0])
    right=min((k for k in indices if k>=frame),default=indices[-1])
    a=np.asarray(keys[str(left)],dtype=float)
    b=np.asarray(keys[str(right)],dtype=float)
    if a.shape!=b.shape: raise ValueError('Region vertex counts differ')
    t=0.0 if left==right else (frame-left)/(right-left)
    return a*(1-t)+b*t

def region_gate(config, frame, size):
    mask=Image.new('L',size,0)
    if frame<int(config['first_frame']):return np.zeros((size[1],size[0]),dtype=float)
    draw=ImageDraw.Draw(mask)
    for region in config['regions']:
        draw.polygon([tuple(p) for p in polygon_for_frame(region['keys'],frame)],fill=255)
    distance=distance_transform_edt(np.asarray(mask)>0)
    t=np.clip(distance/float(config['inside_feather_px']),0,1)
    return t*t*(3-2*t)

def refine_alpha(original, predicted, gate, rgb, ribbon_mask, background_pocket):
    # Never open closed holes in painted clothing/hair. Only model background
    # connected to the left frame edge can suppress the old backdrop residue.
    components, _ = label((predicted < 240) & (gate > 0))
    edge_ids = np.unique(components[:, 0]); edge_ids = edge_ids[edge_ids > 0]
    connected = np.isin(components, edge_ids)
    # The general model sometimes erases the blue flying ribbon. Its reviewed
    # source palette is foreground: keep its original alpha, including dark ink.
    channels=rgb.astype(np.int16)
    red_difference=np.clip((channels[:,:,2]-channels[:,:,0]-18)/14.0,0,1)
    green_difference=np.clip((channels[:,:,2]-channels[:,:,1]-6)/10.0,0,1)
    blue_paint=(red_difference*red_difference*(3-2*red_difference))*(green_difference*green_difference*(3-2*green_difference))*ribbon_mask
    clean=np.where(connected, np.minimum(original,predicted), original).astype(float)
    clean=clean*(1-blue_paint)+original*blue_paint
    local_detail=np.max(maximum_filter(channels,size=(3,3,1))-minimum_filter(channels,size=(3,3,1)),axis=2)
    detail_keep=np.clip((local_detail-8)/16.0,0,1)
    detail_keep=detail_keep*detail_keep*(3-2*detail_keep)
    clean*=1-background_pocket*(1-detail_keep)*(1-blue_paint)
    return np.rint(original.astype(float)-(original.astype(float)-clean)*gate).astype(np.uint8)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--decoded',type=Path,required=True)
    parser.add_argument('--model',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--review',type=Path,required=True)
    parser.add_argument('--predicted-cache',type=Path,help='Reuse retained general alpha from this exact source/model; no inference')
    args=parser.parse_args()
    root=Path(__file__).resolve().parents[2]
    original=root/'assets/art/sword_image_driven_v1'
    config_path=root/'assets/data/sword_image_matte_cleanup.json'
    config=json.loads(config_path.read_text());manifest=json.loads((original/'atlas.json').read_text())
    if args.output.exists() or args.review.exists():raise SystemExit('Refusing to overwrite an existing matte package or review')
    if hashlib.md5(args.model.read_bytes()).hexdigest()!='fc16ebd8b0c10d971d3513d564d01e29':raise SystemExit('Installed general model differs from rembg DisSession contract')
    if sha(original/'source.mp4')!=manifest['source_video_sha256']:raise SystemExit('Original clip hash mismatch')
    if len(manifest['frames'])!=61 or manifest['fps']!=25:raise SystemExit('Unexpected source contract')
    spec=importlib.util.spec_from_file_location('approved_clip_packager',root/'tools/sword_image_driven/package_generated_clip.py')
    packager=importlib.util.module_from_spec(spec);spec.loader.exec_module(packager)
    packager.MEAN=(0.5,0.5,0.5) # installed rembg DisSession; standard deviation remains 1
    session=None
    if args.predicted_cache:
        cached=json.loads((args.predicted_cache/'matte-report.json').read_text())
        if cached['source']['model_sha256']!=sha(args.model) or cached['source']['original_video_sha256']!=manifest['source_video_sha256']:raise SystemExit('Prediction cache source/model mismatch')
    else:session=packager.create_session(args.model)
    args.output.mkdir(parents=True);args.review.mkdir(parents=True)
    pages={p.name:Image.open(p).convert('RGBA') for p in original.glob('atlas-*.png')}
    new_pages={name:page.copy() for name,page in pages.items()}
    records=[];missing=[]
    output_rel=args.output.resolve().relative_to(root)
    for i,entry in enumerate(manifest['frames']):
        page_name=Path(entry['path']).name;x,y,w,h=entry['region']
        rgba=np.asarray(pages[page_name].crop((x,y,x+w,y+h)))
        raw=Image.open(args.decoded/('frame-%05d.png'%i)).convert('RGB')
        if raw.size!=(768,1152) or not np.array_equal(np.asarray(raw.resize((w,h),Image.Resampling.LANCZOS)),rgba[:,:,:3]):raise SystemExit('Decoded RGB disagrees with original atlas at frame %d'%i)
        gate=region_gate(config,i,(w,h))
        alpha=rgba[:,:,3].copy()
        if np.any(gate):
            if args.predicted_cache:
                prediction=np.asarray(Image.open(args.predicted_cache/('general-alpha-%02d.png'%i)).convert('L'))
                if prediction.shape!=(h,w):raise SystemExit('Prediction cache dimensions differ')
            else:
                prediction=packager.trim_alpha(packager.predict_mask(session,raw))
                prediction=np.asarray(Image.fromarray(prediction).resize((w,h),Image.Resampling.LANCZOS))
            Image.fromarray(prediction).save(args.review/('general-alpha-%02d.png'%i))
            ribbon=Image.new('L',(w,h),0)
            ImageDraw.Draw(ribbon).polygon([tuple(p) for p in polygon_for_frame(config['ribbon_protection_keys'],i)],fill=255)
            pocket=Image.new('L',(w,h),0)
            ImageDraw.Draw(pocket).polygon([tuple(p) for p in polygon_for_frame(config['background_pocket_keys'],i)],fill=255)
            pocket_gate=np.clip(distance_transform_edt(np.asarray(pocket)>0)/0.75,0,1)
            alpha=refine_alpha(rgba[:,:,3],prediction,gate,rgba[:,:,:3],np.asarray(ribbon)/255.0,pocket_gate)
        changed=alpha!=rgba[:,:,3]
        if np.any(changed & (gate==0)) or np.any(alpha>rgba[:,:,3]):raise SystemExit('Out-of-region alpha mutation')
        result=rgba.copy();result[:,:,3]=alpha
        frame=Image.fromarray(result);new_pages[page_name].paste(frame,(x,y))
        frame.save(args.review/('rgba-%02d.png'%i))
        flat=Image.new('RGBA',(w,h),(229,224,213,255));flat.alpha_composite(frame);flat.convert('RGB').save(args.review/('flat-%02d.png'%i))
        records.append({'frame':i,'alpha_changed_pixels':int(changed.sum()),'strong_alpha_reductions':int(((rgba[:,:,3].astype(int)-alpha)>64).sum()),'rgb_identical':True,'outside_regions_identical':True,'core_alpha_mean':float(alpha[306:334,:65].mean())})
        if i%10==0:print('alpha refinement',i,flush=True)
    clean_manifest=copy.deepcopy(manifest)
    clean_manifest['files_sha256']={}
    for name,page in new_pages.items():
        page.save(args.output/name)
        clean_manifest['files_sha256']['res://'+str(output_rel/name)]=sha(args.output/name)
    for entry in clean_manifest['frames']:entry['path']='res://'+str(output_rel/Path(entry['path']).name)
    (args.output/'atlas.json').write_text(json.dumps(clean_manifest,indent=2)+'\n')
    source={'version':1,'tool':'refine_clip_matte.py','tool_sha256':sha(Path(__file__)), 'prediction_cache_reused':bool(args.predicted_cache),'offline':True,'cost_rmb':0,'original_manifest':'res://assets/art/sword_image_driven_v1/atlas.json','original_manifest_sha256':sha(original/'atlas.json'),'original_video_sha256':manifest['source_video_sha256'],'model':args.model.name,'model_sha256':sha(args.model),'mean':[0.5,0.5,0.5],'model_contract':'installed rembg DisSession','authored_regions':'res://assets/data/sword_image_matte_cleanup.json','authored_regions_sha256':sha(config_path),'alpha_method':'minimum(original anime alpha, general alpha), only in reviewed left region with 16px inward feather and left-boundary-connected general background; closed holes and blue paint inside the authored flying-ribbon contour protected; reviewed upper backdrop pocket suppressed while retaining local ink/detail','preserved':'original RGB, source video, 61 poses, native25fps, fixed384x576 cells, source anchors, all out-of-region alpha','limits':'Full general mask would erase the thin sword; it is deliberately restricted. Source motion blur and crop cannot be repaired by alpha refinement.'}
    (args.output/'source.json').write_text(json.dumps(source,indent=2)+'\n')
    report={'frames':records,'source':source,'all_rgb_identical':True,'all_outside_regions_identical':True,'original_anchors_and_timing_identical':True}
    (args.review/'matte-report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'output':str(args.output),'review':str(args.review),'frames':len(records),'changed_frames':sum(bool(x['alpha_changed_pixels']) for x in records),'cost_rmb':0}))
if __name__=='__main__':main()
