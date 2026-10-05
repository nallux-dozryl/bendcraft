#!/usr/bin/env python3
"""Source/retained native guards using the established bounded codec runner.

Default source checking never launches a Window, Java, kernel, or actor. Native
guards are opt-in and establish only their literal guard scope, not Java parity
or a gameplay light consumer join.
"""
from pathlib import Path
import argparse
import json
import sys
import test_local_player_effect_entities_codec as H

ROOT=H.ROOT
ENTRY=ROOT/'tests/entity_scene_lighting.bend'
WORK=ROOT/'build/entity-scene-lighting'
H.ENTRY=ENTRY
GUARDS=(
 'epoch mismatch refuses before sampling',
 'raw camera signed zero mismatch refuses',
 'current Core tick guards capture',
 'nonfinite partial cannot publish',
 'stencil dimension mismatch refuses',
 'block acquisition forbids stamped samples',
 'unavailable sky revision remains unavailable',
 'missing resident cell is not fullbright',
 'different actual state IDs refuse',
 'duplicate ordered stencil roles retained',
 'absent environment stays absent',
)

def main(native=False):
 number=1
 while (path:=WORK/'checks'/f'{number:03}').exists():number+=1
 path.mkdir(parents=True)
 before=H.source_pins()
 H.write(path/'sources.json',before)
 processes=[]
 report={'status':'FAILED','processes':processes,'source_manifest':H.pin(path/'sources.json')}
 try:
  def run(argv,label,cap):
   row=H.bounded(path,argv,label,cap);processes.append(row);H.process_ok(row);return row
  row=run([H.BEND,ENTRY,'--check-only'],'ordinary',30)
  H.require('ALL PROOFS CHECK' in Path(row['stdout']['path']).read_text() and
            not Path(row['stderr']['path']).read_bytes(),'Source check did not pass')
  report['status']='SOURCE_PASS'
  report['scope']='Actual lifecycle/sampler + seven full-owner proof definitions + eleven unexecuted guard cases; independent kernel and runtime absent.'
  if native:
   with H.forbid_retries():built=H.Build.ensure_native(ENTRY,path/'native',bend=H.BEND,cache_dir=WORK/'native-cache')
   H.require(built['retries']==0,'Builder retried');H.write(path/'native-build.json',built)
   row=run([path/'native','--gpu','off','--threads','1'],'guards',60)
   H.require(Path(row['stdout']['path']).read_text().splitlines()==['ok '+g for g in GUARDS],
             'Actual guard output differs')
   H.require(not Path(row['stderr']['path']).read_bytes(),'Native stderr not empty')
   report.update(status='NARROW_NATIVE_PASS',guards=len(GUARDS),binary=H.pin(path/'native'),
     scope='Literal epoch/raw stamp/residency/order/missing-environment guards only. No Java levels, full Core image comparison, live consumer, lightmap/AO, OS or durable-light recovery claim.')
  H.require(H.source_pins()==before,'Source graph changed during checking')
  report['source_pins_unchanged']=True
 except Exception as error:
  report['error']=repr(error)
 finally:
  H.write(path/'receipt.json',report)
  H.write(ROOT/'evidence'/f'entity-scene-lighting-{number:03}.json',report)
 print(json.dumps(report,indent=2))
 if report['status']=='FAILED':raise SystemExit(1)

if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('--native',action='store_true')
 args=parser.parse_args();main(args.native)
