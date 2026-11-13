# Build data.json + index.html for the F3→F5 draft: 1 real Draft run (sample_front_001) + mock scenes (예시)
# Usage: python3 prep.py <real_dir> <mock_dir>
#   real_dir: view_F.json, references.jsonl, parsed_output.json, metrics.json, config.json, view_F.png
#             (dry_run_v1: kakao_dryrun/representative_inference + source/integrated_annotation_sample)
#   mock_dir: frontend/frontend/mock (scenes.json, meta.json)
import json, base64, io, sys, os
from PIL import Image
R=(sys.argv[1] if len(sys.argv)>1 else 'real').rstrip('/')+'/'
MK=(sys.argv[2] if len(sys.argv)>2 else '../frontend/mock').rstrip('/')+'/'
a=json.load(open(R+'view_F.json')); ref=[json.loads(l) for l in open(R+'references.jsonl') if 'sample_front_001' in l][0]
pred=json.load(open(R+'parsed_output.json'))['track1']; met=json.load(open(R+'metrics.json')); cfg=json.load(open(R+'config.json'))
im=Image.open(R+'view_F.png').convert('RGB').resize((1280,720)); b=io.BytesIO(); im.save(b,'JPEG',quality=78)
img='data:image/jpeg;base64,'+base64.b64encode(b.getvalue()).decode()
regs=[]
for r in a['regions']:
    regs.append({"id":r['region_id'],"type":r['type'],"polygon":r.get('polygon_xy_norm'),"bbox":r.get('bbox_xyxy_norm'),"geometry_status":r.get('geometry_status')})
C=[r for r in regs if r['type']=='driving_area'][0]
gt_rel={}
for k,v in a['track1']['relations'].items():
    gt_rel[k]={"state":v['state'],"object_ids":v.get('object_ids',[]),"region_ids":[x for x in v.get('region_ids',[]) if x!='F_C'],"reason":v.get('reason') or v.get('evidence')}
pr_rel={k:{"state":v['state'],"object_ids":v['object_ids'],"region_ids":v['region_ids'],"reason":v['reason']} for k,v in pred['relations'].items()}
# map backend error strings to the 5 named fail reasons (unmapped kept raw)
def mapErr(e):
    if e.startswith('required action group'): return 'missing_required'
    if 'outside reference allowed set' in e: return 'unsupported'
    if 'forbidden' in e: return 'forbidden'
    if 'schema' in e or 'parse' in e: return 'invalid'
    if 'disagrees with reference relation' in e: return None  # 명세의 '모순'(자기 판정과의 불일치)과 다름 → 분류 미정
    return None
errs=[{"raw":e,"code":mapErr(e)} for e in met['action_rules']['errors']]
real={"scene_id":"sample_front_001","kind":"real","run":{"name":cfg.get('name'),"quant":cfg.get('quant'),"adapter":cfg.get('adapter_source_run'),"commit":"ef1ed25","branch":"dry_run_v1"},
 "conditions":["주간","보도 U","양방향"],"scene":a['summary'],"image":img,"img_w":1280,"img_h":720,
 "review_status":"Draft","benchmark_eligible":ref['benchmark_eligible'],"not_eligible_reason":ref['reason'],"blockers":met['diagnostics']['benchmark']['blockers'],
 "C":C['polygon'],
 "gt":{"objects":[{"id":o['object_id'],"class":o['class'],"role":o['semantic_role'],"placement":o['placement'],"bbox":o['bbox_xyxy_norm']} for o in a['objects']],
       "regions":[r for r in regs if r['type']!='driving_area'],"relations":gt_rel,"actions":ref['action_rules'],
       "attributes":{k:a['attributes'][k]['value'] for k in ('sidewalk_left','sidewalk_right','traffic_direction','direction_match')}},
 "pred":{"valid":met['strict_schema_valid'],"objects":[{"id":o['object_id'],"class":o['class'],"role":o['semantic_role'],"placement":o['placement'],"bbox":o['bbox_xyxy_norm']} for o in pred['objects']],
       "regions":pred['regions'],"relations":pr_rel,"actions":pred['actions'],"attributes":pred['attributes']},
 "scoring":{"source":"backend evaluate.py (draft_diagnostic_only)","pass":met['action_rules']['pass'],"groups":[met['action_rules']['matched_required_groups'],met['action_rules']['required_groups']],
       "errors":errs,"relations":{k:{"gt":v['expected_draft'],"pred":v['predicted'],"ok":v['match']} for k,v in met['relations'].items()},
       "box_pairs":met['diagnostics']['grounding']['objects']['pairs'],"unmatched_pred":met['diagnostics']['grounding']['objects']['unmatched_prediction_ids'],
       "unmatched_ref":met['diagnostics']['grounding']['objects']['unmatched_reference_ids'],"unmeasurable_regions":met['diagnostics']['grounding']['regions']['unmeasurable_reference_ids'],
       "evidence":{k:v['status'] for k,v in met['diagnostics']['evidence'].items()},"V3":None,"V4":None,"V5":None}}
# mock scenes from earlier generator (예시)
M=json.load(open(MK+'scenes.json'))['scenes']; meta=json.load(open(MK+'meta.json'))
mock=[]
for s in M:
    ref_=s['reference']; p=s['predictions']['base']; sc=s['scoring']['base']
    rel=lambda rels:{r['code']:{"state":r['state'],"object_ids":[e for e in r['evidence'] if e.startswith('o')],"region_ids":[e for e in r['evidence'] if e.startswith('z')]} for r in rels}
    mock.append({"scene_id":s['scene_id'],"kind":"mock","conditions":s['conditions'],"scene":s['scene'],"C":s['C'],
      "review_status":ref_['review_status'] if not s['missing'] else 'Missing',"missing_reason":s['missing'],
      "gt":{"objects":[{"id":o['id'],"class":o['class'],"role":o['kind'].lower(),"placement":o.get('placement',''),"bbox":o['bbox']} for o in ref_['objects']],
            "regions":[{"id":r['id'],"type":r['class'],"bbox":r['bbox'],"polygon":None} for r in ref_['regions']],"relations":rel(ref_['relations']),
            "actions":None if ref_['actions'] is None else {"required_groups":[{"alternatives":[{"code":x[0],"condition":x[1]} for x in g['alts']]} for g in ref_['actions']['required_groups']],
                      "allowed_pairs":[{"code":x[0],"condition":x[1]} for x in ref_['actions']['allowed']],"forbidden_pairs":[{"code":x[0],"condition":x[1]} for x in ref_['actions']['forbidden']]},
            "attributes":ref_['scene']},
      "pred":{"valid":p['valid'],"raw_excerpt":p.get('raw_excerpt'),"objects":[{"id":o['id'],"class":o['class'],"role":o['kind'].lower(),"placement":o.get('placement',''),"bbox":o['bbox']} for o in p['objects']],
            "regions":[{"id":r['id'],"type":r['class'],"bbox":r['bbox']} for r in p['regions']],"relations":rel(p['relations']) if p['valid'] else {},"actions":p['actions'],"attributes":p['scene']},
      "scoring":{"source":"mock gen.py","pass":sc['pass'],"errors":[{"raw":None,"code":c} for c in sc['fail_reasons']],"relations":sc['relations'],
                 "box_pairs":[{"prediction_id":m['pred'],"reference_id":m['gt'],"iou":m['iou']} for m in sc['boxes']['matched']],"unmatched_pred":sc['boxes']['extra'],"unmatched_ref":sc['boxes']['missed'],
                 "unmeasurable_regions":[],"evidence":{k:('match' if v else 'mismatch') for k,v in sc['evidence_match'].items()},"groups":[sum(sc.get('groups_hit',[])),len(sc.get('groups_hit',[]))] if ref_['actions'] else None}})
out={"meta":{"actions":meta['actions'],"conditions":meta['conditions'],"relations":meta['relations'],"fail":meta['fail_reasons']},"scenes":[real]+mock}
json.dump(out,open('data.json','w'),ensure_ascii=False)
here=os.path.dirname(os.path.abspath(__file__))
t=open(os.path.join(here,'template.html'),encoding='utf-8').read()
open(os.path.join(here,'index.html'),'w',encoding='utf-8').write(t.replace('__DATA__',json.dumps(out,ensure_ascii=False),1))
print('scenes',len(out['scenes']),'-> data.json, index.html')
