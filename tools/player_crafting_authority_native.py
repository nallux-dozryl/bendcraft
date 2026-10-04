#!/usr/bin/env python3
"""Prepare exact ordinary Bend C emission and compiler/header/library closure."""
from pathlib import Path
import argparse,json,os
import build_native as B

def main():
 parser=argparse.ArgumentParser();parser.add_argument('entry',type=Path);parser.add_argument('--report',required=True,type=Path);args=parser.parse_args()
 entry=args.entry.resolve();cache=B.ROOT/'build/native-cache'
 for name in ('sources','locks','entries','artifacts'): (cache/name).mkdir(parents=True,exist_ok=True)
 prepared=B._prepare(entry,Path('/Users/chuah/.bend/bin/bend'),dict(os.environ),cache)
 emitted=cache/'sources'/prepared['key_data']['prekey']/'generated.c'
 assert B.file_digest(emitted)==prepared['emitted_c_sha256']
 B.guard_route(emitted.read_text())
 flags=prepared['context']['compiler']['flags']
 assert flags==['-std=c11','-O3','<emitted.c>','-lpthread','-lm','-o','<native>'],flags
 report={k:prepared[k] for k in ('cache_key','key_data','context','emitted_seconds','emitted_c_sha256')}
 report['emitted_file']=str(emitted)
 args.report.parent.mkdir(parents=True,exist_ok=True);args.report.write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
 print(json.dumps({'cache_key':report['cache_key'],'emitted_seconds':report['emitted_seconds'],'emitted_c_sha256':report['emitted_c_sha256']}))

if __name__=='__main__':main()
