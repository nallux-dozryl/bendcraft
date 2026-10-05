#!/usr/bin/env python3
"""Prepare the specific measured save-capture repair in a private actor021 copy.

No working product or original frozen source is edited. The unary recursive
anchor has exactly one affine leaf through arbitrary Nested constructors.
"""
from __future__ import annotations
import argparse, difflib, hashlib, json, shutil
from pathlib import Path
import actor021_arity_prepare as P

ANCHOR = '''type CookingSaveAnchor is Type:
  SaveAnchorData{transient:R.Transient,snapshot:Maybe<&2,PublicationJournal.Snapshot>}
  SaveAnchorNested{inner:CookingSaveAnchor}

'''

SAVED = '''def cooking_saved(anchor:CookingSaveAnchor,
    result:E.State<CookingStorage.Saved> & L.Session & J.Value & E.SaveCompletion) -> State & L.Session & J.Value:
  match anchor:
    case SaveAnchorNested{inner}: cooking_saved(inner,result)
    case SaveAnchorData{transient,snapshot}:
      (stored,session,value,completion) = result
      (cooking_save_completed(from_cooking_bundle(stored,transient),snapshot,completion),session,value)

'''

DELEGATE = '''def cooking_delegate_anchored(definitions:D.Catalog,bodies:List<&2,CookingStorage.Body>,pending:List<&2,CookingStore.Effect>,entities:Maybe<&2,CookingStorage.EntityRecovery>,publication:Maybe<&2,PublicationCodec.Recovery>,anchor:CookingSaveAnchor,+session:L.Session,id:String,
    stored:E.State<IC.Saved>) -> IO(State & L.Session & J.Value):
  L.Session{+peer,sequence,capability} = session
  E.State{base,saved,maximum,catalog} = stored
  do IO<State & L.Session & J.Value>:
    result : E.State<CookingStorage.Saved> & L.Session & J.Value & E.SaveCompletion <-
      E.save_codec_receipt(~CookingStorage.Saved,
        CookingStorage.codec_with(definitions,False{},WG.legacy()),
        E.observe(CookingStorage.Saved,E.State{base,CookingStorage.Saved{saved,bodies,pending,entities,publication},maximum,catalog},peer),
        L.Session{peer,1n+sequence,capability},id)
    return cooking_saved(anchor,result)

def cooking_delegate_bundle(definitions:D.Catalog,bodies:List<&2,CookingStorage.Body>,pending:List<&2,CookingStore.Effect>,entities:Maybe<&2,CookingStorage.EntityRecovery>,publication:Maybe<&2,PublicationCodec.Recovery>,snapshot:Maybe<&2,PublicationJournal.Snapshot>,session:L.Session,id:String,
    result:E.State<IC.Saved> & R.Transient) -> IO(State & L.Session & J.Value):
  (stored,transient) = result
  cooking_delegate_anchored(definitions,bodies,pending,entities,publication,
    SaveAnchorData{transient,snapshot},session,id,stored)

'''

# Preserve the exact measured patch text below. Its 193-word receipt plus the
# one-word anchor forms a 194-word leaf; the recursive carrier itself is one box.
COMPLETED = '''type CompletedSave is Type:
  SaveCompletedData{anchor:CookingSaveAnchor,
    result:E.State<CookingStorage.Saved> & L.Session & J.Value & E.SaveCompletion}
  SaveCompletedNested{inner:CompletedSave}

def cooking_saved(completed:CompletedSave) -> State & L.Session & J.Value:
  match completed:
    case SaveCompletedNested{inner}: cooking_saved(inner)
    case SaveCompletedData{anchor,result}: cooking_saved_anchor(anchor,result)

# Keep the completed affine input closed across the pure-return/IO.pure cut.
# Opening its193-word payload belongs to the pure helper, not this IO scope.
def cooking_saved_io(completed:CompletedSave) -> IO(State & L.Session & J.Value):
  do IO<State & L.Session & J.Value>:
    return cooking_saved(completed)

'''

def prepare(output, completed=False):
    output=output.resolve();output.mkdir(parents=True,exist_ok=False)
    frozen=output/'frozen';frozen.mkdir()
    original=P.NEW
    shutil.copytree(original/'source',frozen/'source')
    shutil.copyfile(original/'comp_instrumented.ts',frozen/'comp_instrumented.ts')
    target=frozen/'source/src/local_player_session.bend';before=target.read_text()
    start=before.index('def cooking_saved(transient:R.Transient,')
    finish=before.index('def cooking_save_prepared(',start)
    saved=SAVED;delegate=DELEGATE;completed_source=''
    if completed:
        saved=saved.replace('def cooking_saved(anchor:', 'def cooking_saved_anchor(anchor:').replace(
            'case SaveAnchorNested{inner}: cooking_saved(inner,result)',
            'case SaveAnchorNested{inner}: cooking_saved_anchor(inner,result)')
        completed_source=COMPLETED
        delegate=delegate.replace('    return cooking_saved(anchor,result)',
            '    cooking_saved_io(SaveCompletedData{anchor,result})')
    after=before[:start]+ANCHOR+saved+completed_source+delegate+before[finish:]
    target.write_text(after)
    patch=''.join(difflib.unified_diff(before.splitlines(True),after.splitlines(True),
        fromfile='a/src/local_player_session.bend',tofile='b/src/local_player_session.bend'))
    (output/'candidate.diff').write_text(patch)
    source_map=json.loads((frozen/'source/source-map.json').read_text())
    source_map['status']='private_overlay'
    source_map['original_actor021_seal_sha256']=source_map.pop('seal_sha256',None)
    source_map['scope']='Private actor021 save-anchor overlay: only Session source changed; other frozen actor021 inputs unchanged.'
    source_map['entry']['lookup']=str(frozen/'source/remote_resource_server.bend')
    source_map['entry']['resolved']=str(frozen/'source/remote_resource_server.bend')
    for row in source_map['files']:
        path=frozen/'source'/row['path'];mapped=row['mapped']
        mapped['lookup']=str(path);mapped['resolved']=str(path)
        mapped['bytes']=path.stat().st_size;mapped['sha256']=P.sha(path)
    P.write(frozen/'source/source-map.json',source_map)
    original_pins=json.loads((original/'source/source-map.json').read_text())
    differences=[]
    for row in original_pins['files']:
        path=frozen/'source'/row['path']
        if P.sha(path)!=row['mapped']['sha256']:differences.append(row['path'])
        if P.sha(original/'source'/row['path'])!=row['mapped']['sha256']:
            raise RuntimeError('Original actor021 changed: '+row['path'])
    if differences!=['src/local_player_session.bend']:raise RuntimeError('Unexpected overlay differences: '+str(differences))
    P.NEW=frozen;P.OLD=original
    P.TARGETS=['src/local_player_session:cooking_delegate_anchored',*P.TARGETS]
    if completed:
        P.TARGETS=['src/local_player_session:cooking_saved_io',
                   'src/local_player_session:cooking_saved_anchor',*P.TARGETS]
    diagnostic=P.prepare(output/'diagnostic')
    record={'schema':1,'status':'private_overlay_prepared','baseline':str(original),
      'original_source_map_sha256':P.sha(original/'source/source-map.json'),
      'changed_paths':differences,'patch':{'path':str(output/'candidate.diff'),'sha256':P.sha(output/'candidate.diff')},
      'before_session_sha256':hashlib.sha256(before.encode()).hexdigest(),'after_session_sha256':P.sha(target),
      'anchor':'Unary recursive SaveAnchorData leaf / SaveAnchorNested single child; complete transient and snapshot retained.',
      'completed_result_boxed':completed,
      'unchanged_contract':'Actual E.save_codec_receipt, E.observe, peer/sequence increment, typed SaveCompletion gate, complete session/JSON result and live owner reconstruction remain the original calls.',
      'working_product_or_original_frozen_edited':False,'diagnostic':diagnostic,
      'candidate_verification':'Pending one original whole-book check and selected-body capture measurement; no native/full-build verdict.'}
    P.write(output/'preparation.json',record);return record

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('output',type=Path);parser.add_argument('--completed',action='store_true');args=parser.parse_args()
    r=prepare(args.output,args.completed);print(json.dumps({'status':r['status'],'patch':r['patch'],'diagnostic':r['diagnostic']}))
