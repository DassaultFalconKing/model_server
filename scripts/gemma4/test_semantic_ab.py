import json, unittest
import semantic_ab as s

def r(case,content,tokens=100,calls=None):
 m={'content':content}
 if calls is not None:m['tool_calls']=calls
 return {'case':case,'elapsed_s':1.0,'response':{'choices':[{'message':m,'finish_reason':'stop'}],'usage':{'completion_tokens':tokens}}}
class T(unittest.TestCase):
 def test_frozen_contract(self):
  c=s.cases('m'); self.assertEqual([x['case'] for x in c],['warmup','long-1024','long-2048','short-128-101','short-128-102','short-128-103','gpu-512']); self.assertEqual([x['seed'] for x in c],[1,8024,9048,101,102,103,777]); self.assertEqual([x['max_tokens'] for x in c],[16,1024,2048,128,128,128,512])
 def test_contract_and_breadth(self):
  x=s.score('long-1024',r('long-1024','Local LLM inference uses memory bandwidth. KV cache and batching change latency. Quantization, prefill, decode and GPU kernels affect throughput.',80)); self.assertEqual(x['required_coverage'],5); self.assertEqual(x['hard'],[]); self.assertGreaterEqual(x['concept_count'],8)
 def test_violation(self):
  x=s.score('gpu-512',r('gpu-512','# GPU\n- batch\n<|tool_call>x',20,[{}])); self.assertIn('heading_or_list',x['hard']); self.assertIn('tool_call',x['hard'])
 def test_length_not_decision(self):
  b={'label':'4','results':[r('gpu-512','GPU transformer performance latency.',20)]}; h={'label':'5','results':[r('gpu-512','GPU transformer optimization uses bandwidth, KV cache, batching, quantization, kernels, prefill, decode, throughput and latency.',40)]}; z=s.compare(b,h); self.assertNotIn('tokens',z['decision_basis']); self.assertGreater(z['pairs'][0]['delta']['concept_count'],0)
 def test_blind_hides_labels(self):
  b={'label':'2026.4','results':[r('short-128-101','Transformer latency.',10)]}; h={'label':'2026.5','results':[r('short-128-101','Transformer throughput.',10)]}; self.assertNotIn('2026.',json.dumps(s.blind(b,h)))
if __name__=='__main__':unittest.main()
