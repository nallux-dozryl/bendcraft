import Base
import ./local_player_effect_tick_recovery.bend as Q
import ./local_player_effect_entities_codec.bend as ECodec
import ./cooking_effect_entities_model.bend as E
import ./item_entity_tick_model.bend as T
import ./vanilla_entity_fields.bend as V
import ./f64.bend as F
import ./support.bend as S
import ./travel.bend as Travel
import ./random.bend as R
import ./nbt.bend as N

# Internal recovery NBT, not vanilla's lossy entity persistence projection.
# NBT's byte/depth/element limits cover this entire tree, including entity data.
# Raw words remain raw: NaN, signed zero, Java int payloads and RNG state are not
# normalized. Runtime tail is explicit and must meet the production [] rule.
def guard(valid:Bool,message:String) -> Result<&2,&2,String,Unit>:
  match valid:
    case True{}: Done{Unit{}}
    case False{}: Fail{"local-player-effect-tick-recovery:" ++ message}
def vector_optional_value(value:Maybe<&2,V.Vec3>) -> N.Value:
  match value:
    case None{}: N.ListTag{11,[]}
    case Some{vector}: N.ListTag{11,[ECodec.vector_value(vector)]}
def vector_optional_read(value:N.Value) -> Result<&2,&2,String,Maybe<&2,V.Vec3>>:
  match value:
    case N.ListTag{11,Nil{}}: Done{None{}}
    case N.ListTag{11,head <> Nil{}}:
      Result.map(&2,&2,String,V.Vec3,Maybe<&2,V.Vec3>,v => Some{v},ECodec.vector_read(head))
    case _: Fail{"local-player-effect-tick-recovery:optional vector"}
def block_value(value:Maybe<&2,Travel.BlockPos>) -> N.Value:
  match value:
    case None{}: N.IntArray{[]}
    case Some{Travel.BlockPos{x,y,z}}: N.IntArray{[x,y,z]}
def block_read(value:N.Value) -> Result<&2,&2,String,Maybe<&2,Travel.BlockPos>>:
  match value:
    case N.IntArray{Nil{}}: Done{None{}}
    case N.IntArray{x <> y <> z <> Nil{}}: Done{Some{Travel.BlockPos{x,y,z}}}
    case _: Fail{"local-player-effect-tick-recovery:optional support block"}
def physical_value(value:T.Physical) -> N.Value:
  T.Physical{gravity,physics,bounce,horizontal,vertical,below,minor,stuck} = value
  N.Compound{[ECodec.member("no_gravity",N.Int{Bool.to_u32(gravity)}),
    ECodec.member("no_physics",N.Int{Bool.to_u32(physics)}),ECodec.member("suppress_bounce",N.Int{Bool.to_u32(bounce)}),
    ECodec.member("horizontal",N.Int{Bool.to_u32(horizontal)}),ECodec.member("vertical",N.Int{Bool.to_u32(vertical)}),
    ECodec.member("below",N.Int{Bool.to_u32(below)}),ECodec.member("minor_horizontal",N.Int{Bool.to_u32(minor)}),
    ECodec.member("stuck",ECodec.vector_value(stuck))]}
def physical_read(value:N.Value) -> Result<&2,&2,String,T.Physical>:
  match value:
    case N.Compound{N.Member{a,N.Int{g}} <> N.Member{b,N.Int{p}} <> N.Member{c,N.Int{s}} <>
        N.Member{d,N.Int{h}} <> N.Member{e,N.Int{v}} <> N.Member{f,N.Int{b0}} <>
        N.Member{g0,N.Int{m}} <> N.Member{h0,stuck} <> Nil{}}:
      do Result<&2,&2,String,T.Physical>:
        guard(ECodec.name(a,"no_gravity") && ECodec.name(b,"no_physics") && ECodec.name(c,"suppress_bounce") &&
          ECodec.name(d,"horizontal") && ECodec.name(e,"vertical") && ECodec.name(f,"below") &&
          ECodec.name(g0,"minor_horizontal") && ECodec.name(h0,"stuck"),"physical schema")
        gravity : Bool <- ECodec.bool_read(g)
        physics : Bool <- ECodec.bool_read(p)
        bounce : Bool <- ECodec.bool_read(s)
        horizontal : Bool <- ECodec.bool_read(h)
        vertical : Bool <- ECodec.bool_read(v)
        below : Bool <- ECodec.bool_read(b0)
        minor : Bool <- ECodec.bool_read(m)
        stuck_vector : V.Vec3 <- ECodec.vector_read(stuck)
        return T.Physical{gravity,physics,bounce,horizontal,vertical,below,minor,stuck_vector}
    case _: Fail{"local-player-effect-tick-recovery:physical schema"}
def base_value(value:T.BaseState) -> N.Value:
  T.BaseState{invulnerable,boarding,water,eye,powder,prior_powder,sprinting,swimming,freezing,silent,last,speed} = value
  N.Compound{[ECodec.member("invulnerable_time",N.Int{invulnerable}),ECodec.member("boarding_cooldown",N.Int{boarding}),
    ECodec.member("was_touching_water",N.Int{Bool.to_u32(water)}),ECodec.member("was_eye_water",N.Int{Bool.to_u32(eye)}),
    ECodec.member("powder_snow",N.Int{Bool.to_u32(powder)}),ECodec.member("was_powder_snow",N.Int{Bool.to_u32(prior_powder)}),
    ECodec.member("sprinting",N.Int{Bool.to_u32(sprinting)}),ECodec.member("swimming",N.Int{Bool.to_u32(swimming)}),
    ECodec.member("freezing",N.Int{Bool.to_u32(freezing)}),ECodec.member("silent",N.Int{Bool.to_u32(silent)}),
    ECodec.member("last_position",vector_optional_value(last)),ECodec.member("speed",ECodec.vector_value(speed))]}
def base_read(value:N.Value) -> Result<&2,&2,String,T.BaseState>:
  match value:
    case N.Compound{N.Member{a,N.Int{inv}} <> N.Member{b,N.Int{board}} <> N.Member{c,N.Int{water}} <>
        N.Member{d,N.Int{eye}} <> N.Member{e,N.Int{powder}} <> N.Member{f,N.Int{prior}} <>
        N.Member{g,N.Int{sprint}} <> N.Member{h,N.Int{swim}} <> N.Member{i,N.Int{freeze}} <>
        N.Member{j,N.Int{silent}} <> N.Member{k,last} <> N.Member{l,speed} <> Nil{}}:
      do Result<&2,&2,String,T.BaseState>:
        guard(ECodec.name(a,"invulnerable_time") && ECodec.name(b,"boarding_cooldown") && ECodec.name(c,"was_touching_water") &&
          ECodec.name(d,"was_eye_water") && ECodec.name(e,"powder_snow") && ECodec.name(f,"was_powder_snow") &&
          ECodec.name(g,"sprinting") && ECodec.name(h,"swimming") && ECodec.name(i,"freezing") &&
          ECodec.name(j,"silent") && ECodec.name(k,"last_position") && ECodec.name(l,"speed"),"base schema")
        w : Bool <- ECodec.bool_read(water)
        ew : Bool <- ECodec.bool_read(eye)
        p : Bool <- ECodec.bool_read(powder)
        wp : Bool <- ECodec.bool_read(prior)
        s : Bool <- ECodec.bool_read(sprint)
        sw : Bool <- ECodec.bool_read(swim)
        fr : Bool <- ECodec.bool_read(freeze)
        si : Bool <- ECodec.bool_read(silent)
        lp : Maybe<&2,V.Vec3> <- vector_optional_read(last)
        sp : V.Vec3 <- ECodec.vector_read(speed)
        return T.BaseState{inv,board,w,ew,p,wp,s,sw,fr,si,lp,sp}
    case _: Fail{"local-player-effect-tick-recovery:base schema"}
def fluid_value(value:T.Fluid) -> N.Value:
  T.Fluid{height,flow,count,present} = value
  N.Compound{[ECodec.member("height",ECodec.double_value(height)),ECodec.member("flow",ECodec.vector_value(flow)),
    ECodec.member("count",N.Int{count}),ECodec.member("present",N.Int{Bool.to_u32(present)})]}
def fluid_read(value:N.Value) -> Result<&2,&2,String,T.Fluid>:
  match value:
    case N.Compound{N.Member{a,height} <> N.Member{b,flow} <> N.Member{c,N.Int{count}} <> N.Member{d,N.Int{present}} <> Nil{}}:
      do Result<&2,&2,String,T.Fluid>:
        guard(ECodec.name(a,"height") && ECodec.name(b,"flow") && ECodec.name(c,"count") && ECodec.name(d,"present"),"fluid schema")
        h : F.F64 <- ECodec.double_read(height)
        v : V.Vec3 <- ECodec.vector_read(flow)
        p : Bool <- ECodec.bool_read(present)
        return T.Fluid{h,v,count,p}
    case _: Fail{"local-player-effect-tick-recovery:fluid schema"}
def fluids_value(value:T.Fluids) -> N.Value:
  T.Fluids{water,lava,eye_water,eye_lava,fast} = value
  N.Compound{[ECodec.member("water",fluid_value(water)),ECodec.member("lava",fluid_value(lava)),
    ECodec.member("eye_water",N.Int{Bool.to_u32(eye_water)}),ECodec.member("eye_lava",N.Int{Bool.to_u32(eye_lava)}),
    ECodec.member("fast_lava",N.Int{Bool.to_u32(fast)})]}
def fluids_read(value:N.Value) -> Result<&2,&2,String,T.Fluids>:
  match value:
    case N.Compound{N.Member{a,water} <> N.Member{b,lava} <> N.Member{c,N.Int{eye_water}} <>
        N.Member{d,N.Int{eye_lava}} <> N.Member{e,N.Int{fast}} <> Nil{}}:
      do Result<&2,&2,String,T.Fluids>:
        guard(ECodec.name(a,"water") && ECodec.name(b,"lava") && ECodec.name(c,"eye_water") &&
          ECodec.name(d,"eye_lava") && ECodec.name(e,"fast_lava"),"fluids schema")
        w : T.Fluid <- fluid_read(water)
        l : T.Fluid <- fluid_read(lava)
        ew : Bool <- ECodec.bool_read(eye_water)
        el : Bool <- ECodec.bool_read(eye_lava)
        f : Bool <- ECodec.bool_read(fast)
        return T.Fluids{w,l,ew,el,f}
    case _: Fail{"local-player-effect-tick-recovery:fluids schema"}
def movement_value(value:T.Movement) -> N.Value:
  T.Movement{from,to,requested} = value
  N.Compound{[ECodec.member("from",ECodec.vector_value(from)),ECodec.member("to",ECodec.vector_value(to)),
    ECodec.member("requested",ECodec.vector_value(requested))]}
def movement_read(value:N.Value) -> Result<&2,&2,String,T.Movement>:
  match value:
    case N.Compound{N.Member{a,from} <> N.Member{b,to} <> N.Member{c,requested} <> Nil{}}:
      do Result<&2,&2,String,T.Movement>:
        guard(ECodec.name(a,"from") && ECodec.name(b,"to") && ECodec.name(c,"requested"),"movement schema")
        f : V.Vec3 <- ECodec.vector_read(from)
        t : V.Vec3 <- ECodec.vector_read(to)
        r : V.Vec3 <- ECodec.vector_read(requested)
        return T.Movement{f,t,r}
    case _: Fail{"local-player-effect-tick-recovery:movement schema"}
def movement_values(values:List<&2,T.Movement>) -> List<&2,N.Value>:
  match values:
    case Nil{}: []
    case head <> rest: movement_value(head) <> movement_values(rest)
def movements_read(values:List<&2,N.Value>) -> Result<&2,&2,String,List<&2,T.Movement>>:
  match values:
    case Nil{}: Done{[]}
    case head <> rest:
      do Result<&2,&2,String,List<&2,T.Movement>>:
        first : T.Movement <- movement_read(head)
        tail : List<&2,T.Movement> <- movements_read(rest)
        return first <> tail
def support_value(value:S.State) -> N.Value:
  S.State{block,ground} = value
  N.Compound{[ECodec.member("main",block_value(block)),ECodec.member("on_ground_no_blocks",N.Int{Bool.to_u32(ground)})]}
def support_read(value:N.Value) -> Result<&2,&2,String,S.State>:
  match value:
    case N.Compound{N.Member{a,block} <> N.Member{b,N.Int{ground}} <> Nil{}}:
      do Result<&2,&2,String,S.State>:
        guard(ECodec.name(a,"main") && ECodec.name(b,"on_ground_no_blocks"),"support schema")
        p : Maybe<&2,Travel.BlockPos> <- block_read(block)
        g : Bool <- ECodec.bool_read(ground)
        return S.State{p,g}
    case _: Fail{"local-player-effect-tick-recovery:support schema"}
def runtime_value(value:T.Runtime) -> N.Value:
  T.Runtime{physical,base,fluids,pending,movements,support,tail} = value
  N.Compound{[ECodec.member("physical",physical_value(physical)),ECodec.member("base",base_value(base)),
    ECodec.member("fluids",fluids_value(fluids)),ECodec.member("pending",N.ListTag{10,movement_values(pending)}),
    ECodec.member("movements",N.ListTag{10,movement_values(movements)}),ECodec.member("support",support_value(support)),
    ECodec.member("tail",N.ListTag{10,[]})]}
def runtime_read(value:N.Value) -> Result<&2,&2,String,T.Runtime>:
  match value:
    case N.Compound{N.Member{a,physical} <> N.Member{b,base} <> N.Member{c,fluids} <>
        N.Member{d,N.ListTag{10,pending}} <> N.Member{e,N.ListTag{10,movements}} <> N.Member{f,support} <>
        N.Member{g,N.ListTag{10,Nil{}}} <> Nil{}}:
      do Result<&2,&2,String,T.Runtime>:
        guard(ECodec.name(a,"physical") && ECodec.name(b,"base") && ECodec.name(c,"fluids") &&
          ECodec.name(d,"pending") && ECodec.name(e,"movements") && ECodec.name(f,"support") && ECodec.name(g,"tail"),"runtime schema")
        p : T.Physical <- physical_read(physical)
        b : T.BaseState <- base_read(base)
        f : T.Fluids <- fluids_read(fluids)
        q : List<&2,T.Movement> <- movements_read(pending)
        m : List<&2,T.Movement> <- movements_read(movements)
        s : S.State <- support_read(support)
        return T.Runtime{p,b,f,q,m,s,[]}
    case _: Fail{"local-player-effect-tick-recovery:runtime schema or noncanonical tail"}
def entry_value(value:T.RuntimeEntry) -> N.Value:
  T.RuntimeEntry{id,runtime} = value
  N.Compound{[ECodec.member("id",N.Int{id}),ECodec.member("runtime",runtime_value(runtime))]}
def entry_read(value:N.Value) -> Result<&2,&2,String,T.RuntimeEntry>:
  match value:
    case N.Compound{N.Member{a,N.Int{id}} <> N.Member{b,runtime} <> Nil{}}:
      do Result<&2,&2,String,T.RuntimeEntry>:
        guard(ECodec.name(a,"id") && ECodec.name(b,"runtime"),"runtime entry schema")
        r : T.Runtime <- runtime_read(runtime)
        return T.RuntimeEntry{id,r}
    case _: Fail{"local-player-effect-tick-recovery:runtime entry schema"}
def entry_values(values:List<&2,T.RuntimeEntry>) -> List<&2,N.Value>:
  match values:
    case Nil{}: []
    case head <> rest: entry_value(head) <> entry_values(rest)
def entries_read(values:List<&2,N.Value>) -> Result<&2,&2,String,List<&2,T.RuntimeEntry>>:
  match values:
    case Nil{}: Done{[]}
    case head <> rest:
      do Result<&2,&2,String,List<&2,T.RuntimeEntry>>:
        first : T.RuntimeEntry <- entry_read(head)
        tail : List<&2,T.RuntimeEntry> <- entries_read(rest)
        return first <> tail
def runtimes_value(value:Maybe<&2,List<&2,T.RuntimeEntry>>) -> N.Value:
  match value:
    case None{}: N.Compound{[ECodec.member("present",N.Int{0})]}
    case Some{entries}: N.Compound{[ECodec.member("present",N.Int{1}),ECodec.member("entries",N.ListTag{10,entry_values(entries)})]}
def runtimes_read(value:N.Value) -> Result<&2,&2,String,Maybe<&2,List<&2,T.RuntimeEntry>>>:
  match value:
    case N.Compound{N.Member{a,N.Int{0}} <> Nil{}}:
      do Result<&2,&2,String,Maybe<&2,List<&2,T.RuntimeEntry>>>:
        guard(ECodec.name(a,"present"),"runtime availability schema")
        return None{}
    case N.Compound{N.Member{a,N.Int{1}} <> N.Member{b,N.ListTag{10,entries}} <> Nil{}}:
      do Result<&2,&2,String,Maybe<&2,List<&2,T.RuntimeEntry>>>:
        guard(ECodec.name(a,"present") && ECodec.name(b,"entries"),"runtime availability schema")
        values : List<&2,T.RuntimeEntry> <- entries_read(entries)
        return Some{values}
    case _: Fail{"local-player-effect-tick-recovery:runtime availability schema"}
def sound_value(value:Maybe<&2,R.Source>) -> N.Value:
  match value:
    case None{}: N.ListTag{10,[]}
    case Some{source}: N.ListTag{10,[ECodec.random_value(source)]}
def sound_read(value:N.Value) -> Result<&2,&2,String,Maybe<&2,R.Source>>:
  match value:
    case N.ListTag{10,Nil{}}: Done{None{}}
    case N.ListTag{10,head <> Nil{}}:
      Result.map(&2,&2,String,R.Source,Maybe<&2,R.Source>,source => Some{source},ECodec.random_read(head))
    case _: Fail{"local-player-effect-tick-recovery:sound availability schema"}
def entity_value(value:N.Root) -> N.Value:
  N.Root{name,payload} = value
  payload
def root(value:Q.Recovery) -> N.Root:
  Q.Recovery{entities,runtimes,sound} = value
  N.Root{ECodec.text("bendex:local-player-effect-tick-recovery"),N.Compound{[ECodec.member("format",N.Int{1}),
    ECodec.member("entities",entity_value(ECodec.root(entities))),ECodec.member("runtimes",runtimes_value(runtimes)),
    ECodec.member("sound",sound_value(sound))]}}
def root_read(value:N.Root) -> Result<&2,&2,String,Q.Recovery>:
  match value:
    case N.Root{name,N.Compound{N.Member{a,N.Int{1}} <> N.Member{b,entities} <> N.Member{c,runtimes} <> N.Member{d,sound} <> Nil{}}}:
      do Result<&2,&2,String,Q.Recovery>:
        guard(ECodec.name(name,"bendex:local-player-effect-tick-recovery") && ECodec.name(a,"format") &&
          ECodec.name(b,"entities") && ECodec.name(c,"runtimes") && ECodec.name(d,"sound"),"root schema")
        e : E.View <- ECodec.root_read(N.Root{ECodec.text("bendex:cooking-effect-entities"),entities})
        r : Maybe<&2,List<&2,T.RuntimeEntry>> <- runtimes_read(runtimes)
        s : Maybe<&2,R.Source> <- sound_read(sound)
        return Q.Recovery{e,r,s}
    case _: Fail{"local-player-effect-tick-recovery:root schema"}
def canonical_runtime(value:T.Runtime) -> Bool:
  T.Runtime{physical,base,fluids,pending,movements,support,tail} = value
  List.is_empty(&2,T.Runtime,tail)
def canonical_entries(values:List<&2,T.RuntimeEntry>) -> Bool:
  match values:
    case Nil{}: True{}
    case T.RuntimeEntry{id,runtime} <> rest: canonical_runtime(runtime) && canonical_entries(rest)
def canonical(value:Maybe<&2,List<&2,T.RuntimeEntry>>) -> Bool:
  match value:
    case None{}: True{}
    case Some{values}: canonical_entries(values)
def encode(limits:N.Limits,+value:Q.Recovery) -> Result<&2,&2,String,List<&2,U32>>:
  Q.Recovery{+entities,+runtimes,+sound} = value
  do Result<&2,&2,String,List<&2,U32>>:
    ECodec.view_nat(entities)
    guard(canonical(runtimes),"noncanonical runtime tail")
    N.encode_with(limits,root(Q.Recovery{entities,runtimes,sound}))
def decoded(result:Result<&2,&2,String,N.Root>) -> Result<&2,&2,String,Q.Recovery>:
  match result:
    case Fail{message}: Fail{"local-player-effect-tick-recovery:NBT:" ++ message}
    case Done{value}: root_read(value)
def decode(limits:N.Limits,bytes:List<&2,U32>) -> Result<&2,&2,String,Q.Recovery>:
  decoded(N.decode_with(limits,bytes))
