#!/usr/bin/env python3
"""Gemma4 2026.4 -> 2026.5 response A/B capture and deterministic semantic checks."""
import argparse, hashlib, json, re, time, urllib.request
from pathlib import Path

LONG='Write a detailed continuous technical discussion of local large-language-model inference, memory bandwidth, KV caching, batching, and latency. Do not use tools, headings, bullet lists, or conclude early. Keep expanding naturally until the {0} token output limit.'
SHORT='Generate a continuous technical explanation of transformer inference performance. Do not use tools, headings, lists, or an early conclusion. Continue until the token limit.'
GPU='Write a continuous detailed technical explanation of GPU transformer inference optimization. Do not use tools, headings, lists, or a conclusion. Keep expanding the explanation until the token limit.'
WARM='Reply with a short sentence confirming readiness.'
SOURCE='scripts/gemma4/benchmark-legacy-prompts.ps1@2d17e36f39412f18df558c49c6bc4661b833f675'
CONCEPTS={
 'bandwidth':r'\bbandwidth\b','kv_cache':r'\bkv\s+(?:cache|caching)\b|\bkey[- ]value\s+cache\b','batching':r'\bbatch(?:ing|es|ed)?\b',
 'latency':r'\blatency\b','throughput':r'\bthroughput\b','prefill':r'\bprefill\b','decode':r'\bdecod(?:e|ing)\b',
 'quantization':r'\bquantiz\w*\b|\bint[248]\b','kernel':r'\bkernels?\b','attention':r'\battention\b','context':r'\bcontext\b',
 'scheduler':r'\bschedul\w*\b','concurrency':r'\bconcurren\w*\b|\bparallel\w*\b','speculative':r'\bspeculative\b',
 'offload':r'\boffload\w*\b','numa':r'\bnuma\b','vram':r'\bvram\b|\bgpu memory\b','compute':r'\bcompute\b|\bflops?\b'}
REQ={
 'long':{'local_llm':r'\blocal\b.{0,50}\b(?:llm|large[- ]language[- ]model|language model)\b','bandwidth':CONCEPTS['bandwidth'],'kv_cache':CONCEPTS['kv_cache'],'batching':CONCEPTS['batching'],'latency':CONCEPTS['latency']},
 'short':{'transformer':r'\btransformer\b','performance':r'\bperformance\b|\bthroughput\b|\blatency\b'},
 'gpu':{'gpu':r'\bgpu\b','transformer':r'\btransformer\b','optimization':r'\boptimi[sz]\w*\b|\bthroughput\b|\blatency\b|\bkernel\b|\bmemory\b'}}
STRUCT=re.compile(r'(?m)^\s*(?:#{1,6}\s+|[-*+]\s+|\d+[.)]\s+)')
CONTROL=re.compile(r'<\|[^>]+\|>|<tool_call\|?>',re.I)
CONCLUDE=re.compile(r'\b(?:in conclusion|to conclude|in summary|to summarize)\b',re.I)
SENT=re.compile(r'(?<=[.!?])\s+')

def cases(model):
 out=[dict(case='warmup',model=model,messages=[{'role':'user','content':WARM}],max_tokens=16,temperature=0,seed=1)]
 for n in (1024,2048): out.append(dict(case=f'long-{n}',model=model,messages=[{'role':'user','content':LONG.format(n)}],max_tokens=n,temperature=.7,seed=7000+n))
 for s in (101,102,103): out.append(dict(case=f'short-128-{s}',model=model,messages=[{'role':'user','content':SHORT}],max_tokens=128,temperature=.7,seed=s))
 out.append(dict(case='gpu-512',model=model,messages=[{'role':'user','content':GPU}],max_tokens=512,temperature=.7,seed=777))
 return out

def post(url,body,timeout):
 data=json.dumps(body,separators=(',',':')).encode(); req=urllib.request.Request(url,data=data,headers={'Content-Type':'application/json'},method='POST'); t=time.monotonic()
 try:
  with urllib.request.urlopen(req,timeout=timeout) as r: raw=r.read(); status=r.status
 except Exception as e: return 0,None,str(e),round(time.monotonic()-t,3)
 text=raw.decode('utf-8','replace')
 try: parsed=json.loads(text)
 except json.JSONDecodeError: parsed=None
 return status,parsed,text,round(time.monotonic()-t,3)

def capture(url,model,label,timeout):
 out=[]; endpoint=url.rstrip('/')+'/chat/completions'
 for c in cases(model):
  body=dict(c); name=body.pop('case'); status,r,raw,elapsed=post(endpoint,body,timeout); out.append({'case':name,'request':body,'http_status':status,'elapsed_s':elapsed,'response':r,'response_raw':raw})
 return {'schema':1,'label':label,'model':model,'source':SOURCE,'results':out}

def family(c): return 'long' if c.startswith('long-') else 'short' if c.startswith('short-') else 'gpu' if c.startswith('gpu-') else 'warmup'
def text(item):
 try: return item['response']['choices'][0]['message'].get('content') or ''
 except (TypeError,KeyError,IndexError): return ''
def tokens(item):
 try: return int(item['response']['usage'].get('completion_tokens') or 0)
 except (TypeError,KeyError,ValueError): return 0

def score(c,item):
 s=text(item); f=family(c); req=REQ.get(f,{}); covered=[k for k,p in req.items() if re.search(p,s,re.I|re.S)]; concepts=[k for k,p in CONCEPTS.items() if re.search(p,s,re.I)]
 hard=[]
 if f!='warmup' and not s.strip(): hard.append('empty')
 if f!='warmup' and STRUCT.search(s): hard.append('heading_or_list')
 try: calls=item['response']['choices'][0]['message'].get('tool_calls') or []
 except (TypeError,KeyError,IndexError): calls=[]
 if f!='warmup' and (calls or '<|tool_call>' in s or '<tool_call' in s): hard.append('tool_call')
 if CONTROL.search(s): hard.append('control_token_leak')
 ss=[re.sub(r'\s+',' ',x.strip().lower()) for x in SENT.split(s) if len(x.strip())>=24]; rep=(len(ss)-len(set(ss)))/len(ss) if ss else 0
 n=tokens(item)
 return {'content':s,'tokens':n,'required_coverage':len(covered),'required_total':len(req),'concept_count':len(concepts),'concept_density':round(len(concepts)*1000/n,3) if n else 0,'repetition':round(rep,4),'hard':hard,'soft':['conclusion'] if f!='warmup' and CONCLUDE.search(s) else []}

def compare(base,head):
 bi={x['case']:x for x in base['results']}; hi={x['case']:x for x in head['results']}; pairs=[]; sums={'hard_regressions':0,'coverage_wins':0,'coverage_losses':0,'concept_wins':0,'concept_losses':0,'repetition_wins':0,'repetition_losses':0}
 for c in [x['case'] for x in cases(base.get('model') or head.get('model') or 'model') if x['case'] in bi and x['case'] in hi]:
  a,b=score(c,bi[c]),score(c,hi[c]); dh=len(b['hard'])-len(a['hard']); dc=b['required_coverage']-a['required_coverage']; db=b['concept_count']-a['concept_count']; dr=b['repetition']-a['repetition']
  sums['hard_regressions']+=dh>0; sums['coverage_wins']+=dc>0; sums['coverage_losses']+=dc<0; sums['concept_wins']+=db>0; sums['concept_losses']+=db<0; sums['repetition_wins']+=dr<0; sums['repetition_losses']+=dr>0
  pairs.append({'case':c,'base':a,'head':b,'delta':{'hard':dh,'coverage':dc,'concept_count':db,'concept_density':round(b['concept_density']-a['concept_density'],3),'repetition':round(dr,4),'tokens':b['tokens']-a['tokens'],'elapsed_s':round(hi[c].get('elapsed_s',0)-bi[c].get('elapsed_s',0),3)}})
 pos=sums['coverage_wins']+sums['concept_wins']+sums['repetition_wins']; neg=sums['coverage_losses']+sums['concept_losses']+sums['repetition_losses']; sums['signal']='REGRESSION' if sums['hard_regressions'] else 'SEMANTIC_GAIN_SIGNAL' if pos>neg else 'TIE' if pos==neg else 'MIXED_OR_REGRESSION'
 return {'schema':1,'base':base.get('label'),'head':head.get('label'),'decision_basis':['hard','required_coverage','concept_count','concept_density','repetition'],'observations_only':['tokens','elapsed_s'],'summary':sums,'pairs':pairs}

def blind(base,head):
 bi={x['case']:x for x in base['results']}; hi={x['case']:x for x in head['results']}; out=[]
 for c in sorted(set(bi)&set(hi)):
  a,b=text(bi[c]),text(hi[c]); swap=hashlib.sha256(c.encode()).digest()[0]&1; A,B=(b,a) if swap else (a,b); out.append({'case':c,'A':A,'B':B})
 return {'instruction':'Blind review: correctness, relevance, useful detail, redundancy, instruction following. Do not reward length by itself.','pairs':out}
def key(base,head): return {c:('A=head,B=base' if hashlib.sha256(c.encode()).digest()[0]&1 else 'A=base,B=head') for c in sorted(set(x['case'] for x in base['results'])&set(x['case'] for x in head['results']))}
def load(p): return json.loads(Path(p).read_text(encoding='utf-8'))
def dump(p,x): Path(p).parent.mkdir(parents=True,exist_ok=True); Path(p).write_text(json.dumps(x,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')

def main():
 ap=argparse.ArgumentParser(); sub=ap.add_subparsers(dest='cmd',required=True); c=sub.add_parser('capture'); c.add_argument('--base-url',default='http://127.0.0.1:8000/v3'); c.add_argument('--model',default='gemma4-26-heretic'); c.add_argument('--label',required=True); c.add_argument('--out',required=True); c.add_argument('--timeout',type=int,default=1200); q=sub.add_parser('compare'); q.add_argument('--base',required=True); q.add_argument('--head',required=True); q.add_argument('--out',required=True); q.add_argument('--blind-out',required=True); q.add_argument('--key-out')
 a=ap.parse_args()
 if a.cmd=='capture': x=capture(a.base_url,a.model,a.label,a.timeout); dump(a.out,x); print(json.dumps({'cases':len(x['results']),'out':a.out})); return 0
 b,h=load(a.base),load(a.head); r=compare(b,h); dump(a.out,r); dump(a.blind_out,blind(b,h)); a.key_out and dump(a.key_out,key(b,h)); print(json.dumps(r['summary'])); return 1 if r['summary']['signal']=='REGRESSION' else 0
if __name__=='__main__': raise SystemExit(main())
