import Base
import ./item_entity_tick_model.bend as T
import ./item_entity_tick_fields.bend as U
import ./item_entity_tick_properties.bend as P
import ./cooking_effect_entities_model.bend as E
import ./cooking_effect_entities_query.bend as Q
import ./inventory.bend as I
import ./campfire_authority_items.bend as CI
import ./f64.bend as F
import ./geometry.bend as A
import ./cooking_effect_geometry.bend as G
import ./random.bend as R
import ./vanilla_entity_fields.bend as V

type MergePair is Data:
  MergePair{+first:E.Record,+second:E.Record,publications:List<&2,T.Publication>}
type Neighbours is Data:
  Neighbours{+record:E.Record,others:List<&2,E.Record>,publications:List<&2,T.Publication>}
def signed_min(+a:U32,+b:U32) -> U32: U.select(U32,a,b,U.signed_lt(a,b))
def signed_max(+a:U32,+b:U32) -> U32: U.select(U32,b,a,U.signed_lt(a,b))
def bits_eq(a:R.Bits64,b:R.Bits64) -> Bool:
  R.Bits64{+ah,+al}=a
  R.Bits64{+bh,+bl}=b
  U32.is_eq(ah,bh) && U32.is_eq(al,bl)
def uuid(a:Maybe<&2,E.Uuid>,b:Maybe<&2,E.Uuid>) -> Bool:
  match a b:
    case None{} None{}: True{}
    case Some{E.Uuid{+am,+al}} Some{E.Uuid{+bm,+bl}}: bits_eq(am,bm) && bits_eq(al,bl)
    case _ _: False{}
def count(slot:I.Slot) -> U32:
  match slot:
    case I.InvEmpty{}: 0
    case I.InvStack{+key,+n}: n
def eligible(+meta:I.ItemMetadata,+record:E.Record) -> Bool:
  match record:
    case E.Item{+c,I.InvStack{+key,+n},+age,+delay,+h,+thrower,+target,+bob}:
      Bool.not(U.removed_common(c)) && U32.is_ne(delay,32767) && U32.is_ne(age,4294934528) && U.signed_lt(age,6000) && U.signed_lt(n,P.maximum(meta))
    case _: False{}
def can_join(+first:E.Record,+second:E.Record,+second_meta:I.ItemMetadata) -> Bool:
  match first second:
    case E.Item{+a,I.InvStack{+ak,+an},+aa,+ad,+ah,+at,+target,+ab} E.Item{+b,I.InvStack{+bk,+bn},+ba,+bd,+bh,+bt,+other,+bb}:
      uuid(target,other) && U.signed_lt(U32.add(an,bn),U32.inc(P.maximum(second_meta))) && I.key_equal(ak,bk)
    case _ _: False{}
# The neighbour survives a tie. The transfer cap is 64 even for a genuine
# component-patched maximum99; signed Math.min and wrap arithmetic are retained.
def transfer(+target:E.Record,+source:E.Record,+maximum:U32) -> MergePair:
  match target source:
    case E.Item{+tc,I.InvStack{+tk,+tn},+ta,+td,+th,+tt,+tg,+tb} E.Item{+sc,I.InvStack{+sk,+sn},+sa,+sd,+sh,+st,+sg,+sb}:
      +amount=signed_min(U32.sub(signed_min(maximum,64),tn),sn)
      +source_count=U32.sub(sn,amount)
      +next_source : E.Record = E.Item{sc,I.InvStack{sk,source_count},sa,sd,sh,st,sg,sb}
      +discard=Bool.not(U.positive(source_count))
      publications : List<&2,T.Publication> = T.Merge{E.common_id(sc),E.common_id(tc),amount} <> U.select(List<&2,T.Publication>,[T.Removed{E.common_id(sc)}],[],discard)
      MergePair{E.Item{tc,I.InvStack{tk,U32.add(tn,amount)},signed_min(ta,sa),signed_max(td,sd),th,tt,tg,tb},U.select(E.Record,U.discard(next_source),next_source,discard),publications}
    case _ _: MergePair{target,source,[]}
def reverse(pair:MergePair) -> MergePair:
  MergePair{+a,+b,+p}=pair
  MergePair{b,a,p}
def survivor(+first:E.Record,+second:E.Record,+maximum:U32,+first_larger:Bool) -> MergePair:
  match first_larger:
    case True{}: transfer(first,second,maximum)
    case False{}: reverse(transfer(second,first,maximum))
def merged(+first:E.Record,+second:E.Record,+maximum:U32,+allowed:Bool) -> MergePair:
  match allowed:
    case False{}: MergePair{first,second,[]}
    case True{}: survivor(first,second,maximum,U.signed_lt(count(U.slot(second)),count(U.slot(first))))
def metadata_for(+context:CI.Context,+record:E.Record) -> Result<&2,&2,T.Error,I.ItemMetadata>:
  match record:
    case E.Item{+c,I.InvStack{+key,+count},+a,+d,+h,+t,+target,+bob}: P.of_key(context,key)
    case _: Fail{T.Refused{"item merge requires an actual nonempty item record"}}
def pair(+context:CI.Context,+first:E.Record,+second:E.Record) -> Result<&2,&2,T.Error,MergePair>:
  do Result<&2,&2,T.Error,MergePair>:
    +fm : I.ItemMetadata <- metadata_for(context,first)
    +sm : I.ItemMetadata <- metadata_for(context,second)
    return merged(first,second,P.maximum(sm),eligible(fm,first) && eligible(sm,second) && can_join(first,second,sm))
def inflate(+box:A.AABB) -> A.AABB:
  A.AABB{+x,+y,+z,+a,+b,+c}=box
  A.AABB{F.sub(x,F.from_f32(0.5)),y,F.sub(z,F.from_f32(0.5)),F.add(a,F.from_f32(0.5)),b,F.add(c,F.from_f32(0.5))}
def candidate_common(+center:E.Record,+other:E.Record,+first_base:E.Common,+second_base:E.Common) -> Bool:
  E.Common{+d,+id,+a,+b,+r,+f,+t,+first,+removed,+accessible,+order}=first_base
  E.Common{+od,+oi,+a,+b,+r,+f,+t,+first,+removed,+oa,+order}=second_base
  String.eq(d,od) && U32.is_ne(id,oi) && oa && A.AABB.intersects(U.body(other),inflate(U.body(center)))
def candidate(+center:E.Record,+other:E.Record) -> Bool: candidate_common(center,other,E.common(center),E.common(other))
def first_hit(hit:Q.Hit,old:Maybe<&2,Q.Hit>) -> Maybe<&2,Q.Hit>: Q.first(hit,old)
def section_error(result:Result<&2,&2,E.Error,Q.SectionKey>) -> Result<&2,&2,T.Error,Q.SectionKey>:
  match result:
    case Done{+k}: Done{k}
    case Fail{+e}: Fail{T.EntityError{e}}
def section_x(+word:U32) -> U32:
  U.select(U32,U32.or(word,4290772992),word,U32.is_ge(word,2097152))
def section_key(point:V.Vec3,order:Nat) -> Q.SectionKey:
  V.Vec3{x,y,z}=point
  Q.SectionKey{section_x(U32.and(U32.shrn(V.floor_word(x),4n),4194303)),U32.and(U32.shrn(V.floor_word(z),4n),4194303),U32.and(U32.shrn(V.floor_word(y),4n),1048575),order}
# Q.less then compares the signed packed-long X field followed by unsigned Z/Y.
def choose_key(+record:E.Record,old:Maybe<&2,Q.Hit>,+common:E.Common) -> Result<&2,&2,T.Error,Maybe<&2,Q.Hit>>:
  E.Common{+d,+id,+a,+b,+r,+f,+t,+first,+removed,+accessible,+order}=common
  Done{Q.first(Q.Hit{id,section_key(U.pos(record),order)},old)}
def choose_hit(+record:E.Record,old:Maybe<&2,Q.Hit>,+good:Bool) -> Result<&2,&2,T.Error,Maybe<&2,Q.Hit>>:
  match good:
    case False{}: Done{old}
    case True{}:
      choose_key(record,old,E.common(record))
def used(values:List<&2,U32>,+id:U32) -> Bool:
  match values:
    case Nil{}: False{}
    case +h <> +t: U32.is_eq(h,id) || used(t,id)
def next_eligible(+context:CI.Context,+head:E.Record,prior:Maybe<&2,Q.Hit>,continue:Maybe<&2,Q.Hit> -> Result<&2,&2,T.Error,Maybe<&2,Q.Hit>>) -> Result<&2,&2,T.Error,Maybe<&2,Q.Hit>>:
  do Result<&2,&2,T.Error,Maybe<&2,Q.Hit>>:
    +meta : I.ItemMetadata <- metadata_for(context,head)
    +found : Maybe<&2,Q.Hit> <- choose_hit(head,prior,eligible(meta,head))
    continue(found)
def next_gate(+context:CI.Context,+head:E.Record,prior:Maybe<&2,Q.Hit>,+good:Bool,continue:Maybe<&2,Q.Hit> -> Result<&2,&2,T.Error,Maybe<&2,Q.Hit>>) -> Result<&2,&2,T.Error,Maybe<&2,Q.Hit>>:
  match good:
    case False{}: continue(prior)
    case True{}: next_eligible(context,head,prior,continue)
def next(values:List<&2,E.Record>,+context:CI.Context,+center:E.Record,+seen:List<&2,U32>,prior:Maybe<&2,Q.Hit>) -> Result<&2,&2,T.Error,Maybe<&2,Q.Hit>>:
  match values:
    case Nil{}: Done{prior}
    case +head <> +rest:
      next_gate(context,head,prior,candidate(center,head) && Bool.not(used(seen,E.record_id(head))) && Bool.not(U.empty(U.slot(head))),p => next(rest,context,center,seen,p))
def lookup_gate(+head:E.Record,+equal:Bool,continue:Unit -> Result<&2,&2,T.Error,E.Record>) -> Result<&2,&2,T.Error,E.Record>:
  match equal:
    case True{}: Done{head}
    case False{}: continue(Unit{})
def lookup(values:List<&2,E.Record>,+id:U32) -> Result<&2,&2,T.Error,E.Record>:
  match values:
    case Nil{}: Fail{T.Refused{"item merge neighbour disappeared from snapshot"}}
    case +head <> +rest: lookup_gate(head,U32.is_eq(E.record_id(head),id),u => lookup(rest,id))
def replace(values:List<&2,E.Record>,+replacement:E.Record) -> List<&2,E.Record>:
  match values:
    case Nil{}: []
    case +head <> +rest: U.select(E.Record,replacement,head,U32.is_eq(E.record_id(head),E.record_id(replacement))) <> replace(rest,replacement)
def next_live(+context:CI.Context,+record:E.Record,records:List<&2,E.Record>,seen:List<&2,U32>,+dead:Bool) -> Result<&2,&2,T.Error,Maybe<&2,Q.Hit>>:
  match dead:
    case True{}: Done{None{}}
    case False{}: next(records,context,record,seen,None{})
def loop_pair(+context:CI.Context,records:List<&2,E.Record>,+seen:List<&2,U32>,publications:List<&2,T.Publication>,pair:MergePair,continue:E.Record -> List<&2,E.Record> -> List<&2,T.Publication> -> Maybe<&2,Q.Hit> -> Result<&2,&2,T.Error,Neighbours>) -> Result<&2,&2,T.Error,Neighbours>:
  MergePair{+record,+other,+events}=pair
  +values=replace(records,other)
  do Result<&2,&2,T.Error,Neighbours>:
    +hit : Maybe<&2,Q.Hit> <- next_live(context,record,values,seen,U.removed(record))
    continue(record,values,List.append(&2,T.Publication,publications,events),hit)
def loop(+left:Nat,+context:CI.Context,+record:E.Record,+records:List<&2,E.Record>,+seen:List<&2,U32>,publications:List<&2,T.Publication>,selection:Maybe<&2,Q.Hit>) -> Result<&2,&2,T.Error,Neighbours>:
  match left selection:
    case _ None{}: Done{Neighbours{record,records,publications}}
    case 0n _: Fail{T.Refused{"item merge query budget exhausted"}}
    case 1n+rest Some{Q.Hit{+id,+key}}:
      do Result<&2,&2,T.Error,Neighbours>:
        +other : E.Record <- lookup(records,id)
        +merged : MergePair <- pair(context,record,other)
        loop_pair(context,records,id <> seen,publications,merged,n => values => events => hit => loop(rest,context,n,values,id <> seen,events,hit))
def neighbours_gate(+context:CI.Context,+left:Nat,+record:E.Record,+records:List<&2,E.Record>,+good:Bool) -> Result<&2,&2,T.Error,Neighbours>:
  match good:
    case False{}: Done{Neighbours{record,records,[]}}
    case True{}:
      do Result<&2,&2,T.Error,Neighbours>:
        +hit : Maybe<&2,Q.Hit> <- next(records,context,record,[],None{})
        loop(left,context,record,records,[],[],hit)
def neighbours(+context:CI.Context,+left:Nat,+record:E.Record,+records:List<&2,E.Record>) -> Result<&2,&2,T.Error,Neighbours>:
  do Result<&2,&2,T.Error,Neighbours>:
    +meta : I.ItemMetadata <- metadata_for(context,record)
    neighbours_gate(context,left,record,records,eligible(meta,record))
