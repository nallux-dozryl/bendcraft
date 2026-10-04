import Base
import ./resource_client_wire.bend as Wire
import ./framing.bend as Framing
import ./resource_client_framing.bend as PrivateFraming
import ./client_presenter.bend as Common
import ./client_controls.bend as Controls
import ./window_input.bend as Input
import ./world_resource_frame.bend as WRF
import ./client_render.bend as Pixels
import ./client_world.bend as World
import ./movement.bend as Movement
import ./f64.bend as Double
import ./png.bend as PNG
import ./compression.bend as Checksum
import ./player_hud.bend as HUD
import ./player_inventory.bend as Inventory
import ./block_resources.bend as Resources
import ./player_presentation.bend as Presentation
import ./player_presentation_native.bend as NativePresentation
import ./player_inventory_screen.bend as Screen
import ./player_menu_input.bend as MenuInput
import ./player_item_definitions.bend as ItemDefinitions
import ./player_item_catalog.bend as ItemCatalog
import ./inventory_key_consumer.bend as Keys

import ./remote_resource_presenter.bend as P
import ./resource_catalog_world.bend as CW
import ./resource_block_catalog.bend as Catalog
import ./generic_resource_world_sample.bend as GS
import ./generic_resource_world_sample_presenter.bend as Draw
import ./generic_resource_world_sample_resources.bend as Session
import ./generic_resource_world_sample_demand.bend as Demand

# Native resource owner/window consumer. Shared transport, hardware-key/menu
# contracts and presentation policy are imported from the real remote client.
# Only the scene sampling/model/resource owner differs from its legacy route.
def frame_description(sample:GS.Sample,config:P.Config) -> IO(Unit):
  GS.Sample{identity,tick,revision,origin,Pixels.Camera{x,y,z,yaw,pitch},cells} = sample
  P.Config{human,frames,width,height,mode,serial,plan,started,menu,keys,physical_keys} = config
  IO.print("catalog.frame|" ++ Nat.show(serial) ++ "|" ++ identity ++ "|" ++ Nat.show(tick) ++ "|" ++
    Nat.show(revision) ++ "|" ++ Nat.show(List.length(&2,GS.Cell,cells)))

def closing(window:Window,assets:Session.Session,link:P.Link,code:U32,message:String) -> IO(Unit):
  do IO<Unit>:
    Window.close(window)
    Session.close(assets)
    P.release_close(link)
    IO.die(Unit,code,message)

def advance(config:P.Config) -> P.Config:
  P.Config{human,frames,width,height,trace,serial,+plan,started,menu,keys,physical_keys} = config
  P.Config{human,Common.remaining(frames),width,height,trace,1n+serial,plan,started,menu,keys,physical_keys}

def scheduled(window:Window,assets:Session.Session,link:P.Link,config:P.Config,captured:Bool,keep:Bool,
    resume:Window -> Session.Session -> P.Link -> P.Config -> Bool -> IO(Unit)) -> IO(Unit):
  match keep:
    case False{}: closing(window,assets,link,0,"client closed")
    case True{}:
      do IO<Unit>:
        IO.sleep(8)
        resume(window,assets,link,config,captured)

def packet_advance(window:Window,assets:Session.Session,link:P.Link,+next:P.Config,captured:Bool,keep:Bool,
    resume:Window -> Session.Session -> P.Link -> P.Config -> Bool -> IO(Unit)) -> IO(Unit):
  P.Config{human,frames,width,height,trace,serial,+plan,started,menu,keys,physical_keys} = next
  scheduled(window,assets,link,next,captured,keep && Common.continuing(frames),resume)

def commands_sent(window:Window,assets:Session.Session,config:P.Config,captured:Bool,keep:Bool,
    result:P.Link & Result<&2,&2,String,Unit>,resume:Window -> Session.Session -> P.Link -> P.Config -> Bool -> IO(Unit)) -> IO(Unit):
  (link,status) = result
  match status:
    case Done{unit}: packet_advance(window,assets,link,advance(config),captured,keep,resume)
    case Fail{message}: closing(window,assets,link,1,"game command: " ++ message)

def packet_sent(window:Window,assets:Session.Session,config:P.Config,captured:Bool,keep:Bool,commands:List<&2,Wire.Command>,
    result:P.Link & Result<&2,&2,String,Wire.Reply>,resume:Window -> Session.Session -> P.Link -> P.Config -> Bool -> IO(Unit)) -> IO(Unit):
  (link,status) = result
  match status:
    case Done{Wire.Ack{epoch,sequence}}:
      do IO<Unit>:
        sent : P.Link & Result<&2,&2,String,Unit> <- P.send_commands(commands,link)
        commands_sent(window,assets,config,captured,keep,sent,resume)
    case Done{other}: closing(window,assets,link,1,"input: Wire:ExpectedAck")
    case Fail{message}: closing(window,assets,link,1,"input: " ++ message)

def packet_flags(assets:Session.Session,link:P.Link,config:P.Config,old:Bool,previous_capture:Bool,keep:Bool,actions:List<&2,Controls.Action>,
    window:Window,+focused:Bool,+captured:Bool,resume:Window -> Session.Session -> P.Link -> P.Config -> Bool -> IO(Unit)) -> IO(Unit):
  +packet = {Controls.Packet{List.reverse(&2,Controls.Action,
    Common.lost_actions(actions,old && Bool.not(focused && captured))),focused,captured}:Controls.Packet}
  do IO<Unit>:
    sent : P.Link & Result<&2,&2,String,Wire.Reply> <- P.call(link,Wire.Input{packet})
    packet_sent(window,assets,config,focused && captured,keep,HUD.packet_commands(packet,previous_capture),sent,resume)

def packet_final(assets:Session.Session,link:P.Link,config:P.Config,old:Bool,previous_capture:Bool,keep:Bool,actions:List<&2,Controls.Action>,
    result:Window & Bool & Bool,resume:Window -> Session.Session -> P.Link -> P.Config -> Bool -> IO(Unit)) -> IO(Unit):
  (window,focused,captured) = result
  packet_flags(assets,link,config,old,previous_capture,keep,actions,window,focused,captured,resume)

def packet_events(assets:Session.Session,link:P.Link,config:P.Config,previous_capture:Bool,result:Window & Bool & Bool & List<&2,Controls.Action>,
    resume:Window -> Session.Session -> P.Link -> P.Config -> Bool -> IO(Unit)) -> IO(Unit):
  (window,captured,keep,actions) = result
  do IO<Unit>:
    status : Window & Bool & Bool <- Input.Native.status(window)
    packet_final(assets,link,config,captured,previous_capture,keep,actions,status,resume)

def packet_initial_flags(assets:Session.Session,link:P.Link,config:P.Config,pending:List<Event>,allow:Bool,old:Bool,
    window:Window,+focused:Bool,+captured:Bool,resume:Window -> Session.Session -> P.Link -> P.Config -> Bool -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    events : Window & Bool & Bool & List<&2,Controls.Action> <- Common.events(pending,window,allow,focused && captured,True{},Common.lost_actions([],old && Bool.not(focused && captured)))
    packet_events(assets,link,config,focused && captured,events,resume)

def packet_initial(assets:Session.Session,link:P.Link,config:P.Config,pending:List<Event>,allow:Bool,old:Bool,
    result:Window & Bool & Bool,resume:Window -> Session.Session -> P.Link -> P.Config -> Bool -> IO(Unit)) -> IO(Unit):
  (window,focused,captured) = result
  packet_initial_flags(assets,link,config,pending,allow,old,window,focused,captured,resume)


def menu_events_sent(assets:Session.Session,+config:P.Config,pending:List<Event>,old:Bool,result:P.MenuResult,
    resume:Window -> Session.Session -> P.Link -> P.Config -> Bool -> IO(Unit)) -> IO(Unit):
  P.Config{+human,frames,width,height,trace,serial,plan,started,previous,keys,physical_keys} = config
  match result:
    case P.MenuResult{window,link,state,False{},Done{unit}}: closing(window,assets,link,0,"client closed")
    case P.MenuResult{window,link,+state,True{},Done{unit}}:
      do IO<Unit>:
        status : Window & Bool & Bool <- Input.Native.status(window)
        packet_initial(assets,link,P.with_menu(config,state),pending,human && MenuInput.capture_allowed(state),old,status,resume)
    case P.MenuResult{window,link,state,keep,Fail{message}}: closing(window,assets,link,1,"menu command: " ++ message)

def menu_intercepted(assets:Session.Session,link:P.Link,+config:P.Config,old:Bool,window:Window,
    batch:MenuInput.Batch,resume:Window -> Session.Session -> P.Link -> P.Config -> Bool -> IO(Unit)) -> IO(Unit):
  P.Config{human,frames,width,height,trace,serial,plan,started,menu,keys,physical_keys} = config
  MenuInput.Batch{state,intents,events} = batch
  do IO<Unit>:
    sent : P.MenuResult <- P.send_menu_intents(intents,window,link,state,human,True{})
    menu_events_sent(assets,config,MenuInput.game_events(events),old,sent,resume)

def menu_intercept(assets:Session.Session,link:P.Link,+config:P.Config,pending:List<Event>,old:Bool,
    result:Window & Bool & Bool,resume:Window -> Session.Session -> P.Link -> P.Config -> Bool -> IO(Unit)) -> IO(Unit):
  P.Config{human,frames,width,height,trace,serial,+plan,started,menu,keys,physical_keys} = config
  (window,focused,captured) = result
  menu_intercepted(assets,link,config,old,window,MenuInput.packet_keys(physical_keys,keys,menu,pending,
    MenuInput.viewport(Presentation.hud_viewport(plan)),focused,captured),resume)

def input_presented(window:Window,assets:Session.Session,link:P.Link,+config:P.Config,captured:Bool,+image:Image,pending:List<Event>,
    resume:Window -> Session.Session -> P.Link -> P.Config -> Bool -> IO(Unit)) -> IO(Unit):
  P.Config{+human,frames,width,height,trace,serial,+plan,started,menu,keys,physical_keys} = config
  do IO<Unit>:
    P.image_description(image,config)
    window : Window <- Common.window_policy(window,human)
    status : Window & Bool & Bool <- Input.Native.status(window)
    menu_intercept(assets,link,config,Presentation.native_events(pending,plan),captured,status,resume)

def traced(window:Window,assets:Session.Session,link:P.Link,config:P.Config,captured:Bool,image:Image,pending:List<Event>,
    status:Result<&2,&2,String,Unit>,resume:Window -> Session.Session -> P.Link -> P.Config -> Bool -> IO(Unit)) -> IO(Unit):
  match status:
    case Fail{message}: closing(window,assets,link,1,message)
    case Done{unit}: input_presented(window,assets,link,config,captured,image,pending,resume)

def presented(assets:Session.Session,link:P.Link,+config:P.Config,captured:Bool,result:Window & Image & List<Event>,
    resume:Window -> Session.Session -> P.Link -> P.Config -> Bool -> IO(Unit)) -> IO(Unit):
  P.Config{human,frames,width,height,mode,serial,plan,started,menu,keys,physical_keys} = config
  (window,+image,pending) = result
  do IO<Unit>:
    now : U32 <- NativePresentation.Native.milliseconds()
    IO.print("client.timing|" ++ Nat.show(serial) ++ "|" ++ U32.show(U32.sub(now,started)))
    status : Result<&2,&2,String,Unit> <- P.trace(image,config)
    traced(window,assets,link,config,captured,image,pending,status,resume)

def drawn(window:Window,link:P.Link,+config:P.Config,captured:Bool,view:HUD.View,screen:Maybe<&2,Screen.View>,result:Session.Session & Result<&2,&2,String,Image>,
    resume:Window -> Session.Session -> P.Link -> P.Config -> Bool -> IO(Unit)) -> IO(Unit):
  P.Config{human,frames,width,height,trace,serial,+plan,started,menu,keys,physical_keys} = config
  (assets,status) = result
  match status:
    case Fail{message}: closing(window,assets,link,1,"render: " ++ message)
    case Done{image}:
      do IO<Unit>:
        shown : Window & Image & List<Event> <- Window.frame(window,
          MenuInput.draw(HUD.compose(image,view,plan),menu,screen,Presentation.hud_viewport(plan)))
        presented(assets,link,config,captured,shown,resume)

# Textures and catalog values are immutable Data. Retain their lists while
# restoring the sole affine Session.Session owner before world rendering begins.
def asset_hud_view(assets:CW.Assets,snapshot:Inventory.Snapshot) -> CW.Assets & HUD.View:
  match assets snapshot:
    case CW.Assets{Pixels.Assets{+textures},Catalog.Catalog{identity,entries,
        Resources.Catalog{roots,source,models,+sprites,context,usage}},count} Inventory.Snapshot{selected,slots,abilities}:
      (CW.Assets{Pixels.Assets{textures},Catalog.Catalog{identity,entries,Resources.Catalog{roots,source,models,sprites,context,usage}},count},
        HUD.prepare(selected,slots,HUD.icons(textures,sprites)))

def asset_menu_views(assets:CW.Assets,+menu:MenuInput.State) -> CW.Assets & Result<&2,&1,String,HUD.View & Maybe<&2,Screen.View>>:
  match assets menu:
    case CW.Assets{Pixels.Assets{+textures},Catalog.Catalog{identity,entries,
        Resources.Catalog{roots,source,models,+sprites,context,usage}},count}
        MenuInput.State{controller,Some{Inventory.MenuSnapshot{Inventory.Persisted{Inventory.Snapshot{selected,slots,abilities},equipment,status},craft,carried,result,opened,revision}},catalog}:
      +icons = HUD.icons(textures,sprites)
      (CW.Assets{Pixels.Assets{textures},Catalog.Catalog{identity,entries,Resources.Catalog{roots,source,models,sprites,context,usage}},count},
        Done{(HUD.prepare(selected,slots,icons),MenuInput.view(menu,[],icons))})
    case other _:
      (other,Fail{"no authoritative menu snapshot"})

def hud_owned(value:CW.Assets & HUD.View,owner:Demand.Owner,config:Session.Config) -> Session.Session & HUD.View:
  (next,view) = value
  (Session.Session{owner,next,config},view)

def hud_view(session:Session.Session,snapshot:Inventory.Snapshot) -> Session.Session & HUD.View:
  Session.Session{owner,assets,config} = session
  hud_owned(asset_hud_view(assets,snapshot),owner,config)

def menu_owned(value:CW.Assets & Result<&2,&1,String,HUD.View & Maybe<&2,Screen.View>>,owner:Demand.Owner,config:Session.Config) -> Session.Session & Result<&2,&1,String,HUD.View & Maybe<&2,Screen.View>>:
  (next,status) = value
  (Session.Session{owner,next,config},status)

def menu_views(session:Session.Session,menu:MenuInput.State) -> Session.Session & Result<&2,&1,String,HUD.View & Maybe<&2,Screen.View>>:
  Session.Session{owner,assets,config} = session
  menu_owned(asset_menu_views(assets,menu),owner,config)

def inventory_timed(window:Window,assets:Session.Session,link:P.Link,+config:P.Config,captured:Bool,+sample:GS.Sample,
    view:HUD.View,screen:Maybe<&2,Screen.View>,begin:U32,
    resume:Window -> Session.Session -> P.Link -> P.Config -> Bool -> IO(Unit)) -> IO(Unit):
  P.Config{human,frames,width,height,trace,serial,plan,started,menu,keys,physical_keys} = config
  +timed : P.Config = P.Config{human,frames,width,height,trace,serial,plan,begin,menu,keys,physical_keys}
  do IO<Unit>:
    frame_description(sample,timed)
    drawn(window,link,timed,captured,view,screen,Session.draw(sample,assets,width,height),resume)

def inventory_draw(window:Window,link:P.Link,+config:P.Config,captured:Bool,+sample:GS.Sample,
    prepared:Session.Session & Result<&2,&1,String,HUD.View & Maybe<&2,Screen.View>>,resume:Window -> Session.Session -> P.Link -> P.Config -> Bool -> IO(Unit)) -> IO(Unit):
  P.Config{human,frames,width,height,trace,serial,+plan,started,menu,keys,physical_keys} = config
  (assets,status) = prepared
  match status:
    case Fail{message}: closing(window,assets,link,1,message)
    case Done{Tuple{view,screen}}:
      do IO<Unit>:
        begin : U32 <- NativePresentation.Native.milliseconds()
        inventory_timed(window,assets,link,config,captured,sample,view,screen,begin,resume)

def inventoried(window:Window,assets:Session.Session,+config:P.Config,captured:Bool,sample:GS.Sample,
    result:P.Link & Result<&2,&2,String,Wire.Reply>,resume:Window -> Session.Session -> P.Link -> P.Config -> Bool -> IO(Unit)) -> IO(Unit):
  (link,status) = result
  match status:
    case Done{Wire.MenuReply{epoch,sequence,accepted,message,snapshot}}:
      +menu = MenuInput.observed(P.menu_state(config),snapshot)
      inventory_draw(window,link,P.with_menu(config,menu),captured,sample,menu_views(assets,menu),resume)
    case Done{other}: closing(window,assets,link,1,"inventory query: Wire:ExpectedMenu")
    case Fail{message}: closing(window,assets,link,1,"inventory query: " ++ message)

def resources_ready(window:Window,link:P.Link,+config:P.Config,captured:Bool,sample:GS.Sample,
    result:Session.Session & Result<&2,&2,Catalog.Error,Unit>,
    resume:Window -> Session.Session -> P.Link -> P.Config -> Bool -> IO(Unit)) -> IO(Unit):
  (assets,status) = result
  match status:
    case Fail{error}: closing(window,assets,link,1,"resource demand: " ++ Draw.error_text(error))
    case Done{unit}:
      do IO<Unit>:
        reply : P.Link & Result<&2,&2,String,Wire.Reply> <- P.call(link,Wire.MenuInspect{})
        inventoried(window,assets,config,captured,sample,reply,resume)

def snapshot_ready(window:Window,assets:Session.Session,link:P.Link,+config:P.Config,captured:Bool,+sample:GS.Sample,
    resume:Window -> Session.Session -> P.Link -> P.Config -> Bool -> IO(Unit)) -> IO(Unit):
  P.Config{human,frames,width,height,trace,serial,plan,started,menu,keys,physical_keys} = config
  do IO<Unit>:
    prepared:Session.Session & Result<&2,&2,Catalog.Error,Unit> <- Session.ensure(sample,width,height,assets)
    resources_ready(window,link,config,captured,sample,prepared,resume)

def sampled(window:Window,assets:Session.Session,config:P.Config,captured:Bool,result:P.Link & Result<&2,&2,String,Wire.Reply>,
    resume:Window -> Session.Session -> P.Link -> P.Config -> Bool -> IO(Unit)) -> IO(Unit):
  (link,status) = result
  match status:
    case Fail{message}: closing(window,assets,link,1,"frame query: " ++ message)
    case Done{Wire.CatalogFrameReply{epoch,sequence,sample}}: snapshot_ready(window,assets,link,config,captured,sample,resume)
    case Done{other}: closing(window,assets,link,1,"frame query: Wire:ExpectedFrame")

def query_planned(window:Window,assets:Session.Session,link:P.Link,+config:P.Config,captured:Bool,valid:Bool,
    resume:Window -> Session.Session -> P.Link -> P.Config -> Bool -> IO(Unit)) -> IO(Unit):
  match config valid:
    case _ False{}: closing(window,assets,link,1,"drawable dimensions exceed the configured presentation allocation policy")
    case P.Config{human,frames,width,height,trace,serial,plan,started,menu,keys,physical_keys} True{}:
      do IO<Unit>:
        reply : P.Link & Result<&2,&2,String,Wire.Reply> <- P.call(link,Wire.FrameCatalog{width,height})
        sampled(window,assets,config,captured,reply,resume)

def planned(assets:Session.Session,link:P.Link,+config:P.Config,captured:Bool,
    result:Window & Presentation.Geometry,resume:Window -> Session.Session -> P.Link -> P.Config -> Bool -> IO(Unit)) -> IO(Unit):
  P.Config{+human,frames,width,height,trace,serial,Presentation.Plan{+settings,viewport,sw,sh,pw,ph},started,menu,keys,physical_keys} = config
  (actual,+geometry) = result
  +next_plan = Presentation.plan(settings,geometry,human)
  +next_width = Presentation.scene_width(next_plan)
  +next_height = Presentation.scene_height(next_plan)
  +next : P.Config = P.Config{human,frames,next_width,next_height,trace,serial,next_plan,started,menu,keys,physical_keys}
  query_planned(actual,assets,link,next,captured,
    Presentation.geometry_valid(geometry) &&
      Presentation.dimensions(Presentation.output_width(next_plan),Presentation.output_height(next_plan)),resume)

@unsafe
def loop(window:Window,assets:Session.Session,link:P.Link,+config:P.Config,captured:Bool) -> IO(Unit):
  do IO<Unit>:
    actual : Window & Presentation.Geometry <- NativePresentation.measure(window)
    planned(assets,link,config,captured,actual,w => a => l => c => capture => loop(w,a,l,c,capture))

def starting(window:Window,assets:Session.Session,link:P.Link,+config:P.Config,captured:Bool,sample:GS.Sample) -> IO(Unit):
  P.Config{human,frames,width,height,trace,serial,+plan,started,menu,keys,physical_keys} = config
  match frames:
    case Some{0n}: closing(window,assets,link,0,"client closed")
    case _: snapshot_ready(window,assets,link,config,captured,sample,w => a => l => c => capture => loop(w,a,l,c,capture))

def captured(assets:Session.Session,link:P.Link,config:P.Config,sample:GS.Sample,result:Window & Bool) -> IO(Unit):
  (window,capture) = result
  starting(window,assets,link,config,capture,sample)

def capture_configured(window:Window,assets:Session.Session,link:P.Link,+config:P.Config,sample:GS.Sample,valid:Bool) -> IO(Unit):
  match config valid:
    case _ False{}: closing(window,assets,link,1,"drawable/content dimensions exceed the configured presentation allocation policy")
    case P.Config{+human,frames,width,height,trace,serial,plan,started,menu,keys,physical_keys} True{}:
      do IO<Unit>:
        actual : Window & Bool <- Input.capture(window,human)
        captured(assets,link,config,sample,actual)

def configured_window(assets:Session.Session,link:P.Link,+config:P.Config,sample:GS.Sample,
    actual:Window & Presentation.Geometry) -> IO(Unit):
  P.Config{+human,frames,width,height,trace,serial,Presentation.Plan{+settings,viewport,sw,sh,pw,ph},started,menu,keys,physical_keys} = config
  (window,+geometry) = actual
  +plan = Presentation.plan(settings,geometry,human)
  +next : P.Config = P.Config{human,frames,Presentation.scene_width(plan),Presentation.scene_height(plan),trace,serial,plan,started,menu,keys,physical_keys}
  capture_configured(window,assets,link,next,sample,Presentation.geometry_valid(geometry) &&
    Presentation.dimensions(Presentation.output_width(plan),Presentation.output_height(plan)))

def keys_enabled(assets:Session.Session,link:P.Link,config:P.Config,sample:GS.Sample,result:Window & Bool) -> IO(Unit):
  P.Config{human,frames,width,height,trace,serial,plan,started,menu,keys,previous} = config
  (window,enabled) = result
  do IO<Unit>:
    actual : Window & Presentation.Geometry <- NativePresentation.measure(window)
    configured_window(assets,link,P.Config{human,frames,width,height,trace,serial,plan,started,menu,keys,enabled},sample,actual)

def opened(assets:Session.Session,link:P.Link,+config:P.Config,sample:GS.Sample,result:Result<&1,&1,U32 & String,Window>) -> IO(Unit):
  P.Config{+human,frames,width,height,trace,serial,Presentation.Plan{Presentation.Settings{+ow,+oh,percent,scale,+native,+fullscreen},viewport,sw,sh,pw,ph},started,menu,keys,physical_keys} = config
  match result:
    case Fail{(code,message)}:
      do IO<Unit>:
        Session.close(assets)
        P.release_close(link)
        IO.die(Unit,code,"window open: " ++ message)
    case Done{window}:
      do IO<Unit>:
        configured : Window <- NativePresentation.Native.configure(window,ow,oh,native,fullscreen,human)
        keyed : Window & Bool <- NativePresentation.Native.inventory_keys(configured)
        keys_enabled(assets,link,config,sample,keyed)

def open_catalogued_valid(assets:Session.Session,link:P.Link,sample:GS.Sample,+human:Bool,frames:Maybe<&2,Nat>,+settings:Presentation.Settings,catalog:ItemDefinitions.Catalog,keys:Keys.Profile) -> IO(Unit):
  Presentation.Settings{+ow,+oh,percent,scale,native,fullscreen} = settings
  +plan = Presentation.plan(settings,Presentation.Geometry{ow,oh,ow,oh},human)
  do IO<Unit>:
    mode : Result<&1,&1,U32 & String,String> <- IO.get_env("BEND_MINECRAFT_FRAME_DIR")
    window : Result<&1,&1,U32 & String,Window> <- Window.open("Minecraft 26.3 — remote LocalPlayer resource client",
      PNG.choose(U32,960,PNG.choose(U32,512,ow,U32.is_eq(ow,128) && U32.is_eq(oh,128)),human),
      PNG.choose(U32,540,PNG.choose(U32,512,oh,U32.is_eq(ow,128) && U32.is_eq(oh,128)),human))
    opened(assets,link,P.Config{human,frames,Presentation.scene_width(plan),Presentation.scene_height(plan),P.trace_mode(mode),0n,plan,0,MenuInput.new(catalog),keys,False{}},sample,window)

def open_catalogued_checked(assets:Session.Session,link:P.Link,sample:GS.Sample,human:Bool,frames:Maybe<&2,Nat>,settings:Presentation.Settings,catalog:ItemDefinitions.Catalog,
    result:Result<&2,&2,String,Keys.Profile>) -> IO(Unit):
  match result:
    case Fail{message}:
      do IO<Unit>:
        Session.close(assets)
        P.release_close(link)
        IO.die(Unit,1,message)
    case Done{keys}: open_catalogued_valid(assets,link,sample,human,frames,settings,catalog,keys)

# Profiles are fixed for the lifetime of this window. Rebinding a held input
# requires a release/reset transition before opening a new profile.
def open_catalogued_bindings(assets:Session.Session,link:P.Link,sample:GS.Sample,human:Bool,frames:Maybe<&2,Nat>,settings:Presentation.Settings,catalog:ItemDefinitions.Catalog,keys:Keys.Profile) -> IO(Unit):
  open_catalogued_checked(assets,link,sample,human,frames,settings,catalog,Keys.validate(keys))

def open_catalogued(assets:Session.Session,link:P.Link,sample:GS.Sample,human:Bool,frames:Maybe<&2,Nat>,settings:Presentation.Settings,catalog:ItemDefinitions.Catalog) -> IO(Unit):
  open_catalogued_bindings(assets,link,sample,human,frames,settings,catalog,Keys.defaults())

def catalog_loaded(assets:Session.Session,link:P.Link,sample:GS.Sample,human:Bool,frames:Maybe<&2,Nat>,settings:Presentation.Settings,
    result:Result<&2,&2,String,ItemDefinitions.Catalog>) -> IO(Unit):
  match result:
    case Fail{message}:
      do IO<Unit>:
        Session.close(assets)
        P.release_close(link)
        IO.die(Unit,1,message)
    case Done{catalog}: open_catalogued(assets,link,sample,human,frames,settings,catalog)

def catalog_loaded_bindings(assets:Session.Session,link:P.Link,sample:GS.Sample,human:Bool,frames:Maybe<&2,Nat>,settings:Presentation.Settings,keys:Keys.Profile,
    result:Result<&2,&2,String,ItemDefinitions.Catalog>) -> IO(Unit):
  match result:
    case Fail{message}:
      do IO<Unit>:
        Session.close(assets)
        P.release_close(link)
        IO.die(Unit,1,message)
    case Done{catalog}: open_catalogued_bindings(assets,link,sample,human,frames,settings,catalog,keys)

def open_item_table_bindings(assets:Session.Session,link:P.Link,sample:GS.Sample,human:Bool,frames:Maybe<&2,Nat>,settings:Presentation.Settings,path:String,keys:Keys.Profile) -> IO(Unit):
  do IO<Unit>:
    catalog : Result<&2,&2,String,ItemDefinitions.Catalog> <- ItemCatalog.load(path)
    catalog_loaded_bindings(assets,link,sample,human,frames,settings,keys,catalog)

def open_item_table(assets:Session.Session,link:P.Link,sample:GS.Sample,human:Bool,frames:Maybe<&2,Nat>,settings:Presentation.Settings,path:String) -> IO(Unit):
  open_item_table_bindings(assets,link,sample,human,frames,settings,path,Keys.defaults())

def open_settings(assets:Session.Session,link:P.Link,sample:GS.Sample,human:Bool,frames:Maybe<&2,Nat>,settings:Presentation.Settings) -> IO(Unit):
  open_item_table(assets,link,sample,human,frames,settings,"generated/reference_item_metadata.tsv")

def open(assets:Session.Session,link:P.Link,sample:GS.Sample,+human:Bool,frames:Maybe<&2,Nat>,width:U32,height:U32) -> IO(Unit):
  open_settings(assets,link,sample,human,frames,Presentation.Settings{width,height,100,1,False{},False{}})
