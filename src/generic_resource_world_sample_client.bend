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
import ./generic_resource_world_sample_resource_transport.bend as ResourceTransport
import ./generic_resource_world_sample_demand.bend as Demand
import ./player_cooking_client_input.bend as CookingInput
import ./player_cooking_menu_screen.bend as CookingScreen
import ./player_cooking_menu.bend as CookingMenu

# Keep the complete native Presenter configuration closed across IO cuts.
# The recursive tail makes this local presentation owner one runtime box while
# the actual metadata stays the same shared Presenter DTO. Actual tails are empty.
type Config is Data:
  Config{value:P.Config,tail:List<&2,Config>}

def native_config(value:Config) -> P.Config:
  Config{config,tail} = value
  config

def with_menu(value:Config,menu:MenuInput.State) -> Config:
  Config{config,tail} = value
  Config{P.with_menu(config,menu),tail}

# Pure projections and updates leave the recursive Config closed at IO cuts.
def with_native(value:Config,next:P.Config) -> Config:
  Config{previous,tail} = value
  Config{next,tail}

def with_cooking(value:Config,cooking:CookingInput.State) -> Config:
  Config{config,tail} = value
  Config{P.with_cooking(config,cooking),tail}

def config_cooking(value:Config) -> CookingInput.State:
  Config{config,tail} = value
  P.cooking_state(config)

def config_human(value:Config) -> Bool:
  Config{P.Config{human,frames,width,height,trace,serial,plan,started,menu,keys,physical_keys,cooking},tail} = value
  human

def config_frames(value:Config) -> Maybe<&2,Nat>:
  Config{P.Config{human,frames,width,height,trace,serial,plan,started,menu,keys,physical_keys,cooking},tail} = value
  frames

def config_width(value:Config) -> U32:
  Config{P.Config{human,frames,width,height,trace,serial,plan,started,menu,keys,physical_keys,cooking},tail} = value
  width

def config_height(value:Config) -> U32:
  Config{P.Config{human,frames,width,height,trace,serial,plan,started,menu,keys,physical_keys,cooking},tail} = value
  height

def config_serial(value:Config) -> Nat:
  Config{P.Config{human,frames,width,height,trace,serial,plan,started,menu,keys,physical_keys,cooking},tail} = value
  serial

def config_started(value:Config) -> U32:
  Config{P.Config{human,frames,width,height,trace,serial,plan,started,menu,keys,physical_keys,cooking},tail} = value
  started

def config_menu(value:Config) -> MenuInput.State:
  Config{P.Config{human,frames,width,height,trace,serial,plan,started,menu,keys,physical_keys,cooking},tail} = value
  menu

def config_plan(value:Config) -> Presentation.Plan:
  Config{P.Config{human,frames,width,height,trace,serial,plan,started,menu,keys,physical_keys,cooking},tail} = value
  plan

def config_settings(value:Config) -> Presentation.Settings:
  Config{P.Config{human,frames,width,height,trace,serial,Presentation.Plan{settings,viewport,sw,sh,pw,ph},started,menu,keys,physical_keys,cooking},tail} = value
  settings

def config_events(value:Config,pending:List<Event>) -> List<Event>:
  Config{P.Config{human,frames,width,height,trace,serial,plan,started,menu,keys,physical_keys,cooking},tail} = value
  Presentation.native_events(pending,plan)

def with_started(value:Config,begin:U32) -> Config:
  Config{P.Config{human,frames,width,height,trace,serial,plan,started,menu,keys,physical_keys,cooking},tail} = value
  Config{P.Config{human,frames,width,height,trace,serial,plan,begin,menu,keys,physical_keys,cooking},tail}

def with_physical_keys(value:Config,enabled:Bool) -> Config:
  Config{P.Config{human,frames,width,height,trace,serial,plan,started,menu,keys,physical_keys,cooking},tail} = value
  Config{P.Config{human,frames,width,height,trace,serial,plan,started,menu,keys,enabled,cooking},tail}

def with_geometry(value:Config,geometry:Presentation.Geometry) -> Config:
  Config{P.Config{+human,frames,width,height,trace,serial,Presentation.Plan{settings,viewport,sw,sh,pw,ph},started,menu,keys,physical_keys,cooking},tail} = value
  +plan = Presentation.plan(settings,geometry,human)
  Config{P.Config{human,frames,Presentation.scene_width(plan),Presentation.scene_height(plan),trace,serial,plan,started,menu,keys,physical_keys,cooking},tail}

def config_menu_batch(value:Config,pending:List<Event>,focused:Bool,captured:Bool) -> MenuInput.Batch:
  Config{P.Config{human,frames,width,height,trace,serial,plan,started,menu,keys,physical_keys,cooking},tail} = value
  MenuInput.packet_keys(physical_keys,keys,menu,pending,MenuInput.viewport(Presentation.hud_viewport(plan)),focused,captured)

def config_cooking_batch(value:Config,pending:List<Event>,focused:Bool,captured:Bool) -> CookingInput.Batch:
  Config{P.Config{human,frames,width,height,trace,serial,plan,started,menu,keys,physical_keys,cooking},tail} = value
  CookingInput.packet_keys(physical_keys,keys,cooking,pending,MenuInput.viewport(Presentation.hud_viewport(plan)),focused,captured)

def config_image(value:Config,image:Image,view:HUD.View,screen:Maybe<&2,Screen.View>) -> Image:
  Config{P.Config{human,frames,width,height,trace,serial,+plan,started,menu,keys,physical_keys,cooking},tail} = value
  MenuInput.draw(HUD.compose(image,view,plan),menu,screen,Presentation.hud_viewport(plan))

# Native resource owner/window consumer. Shared transport, hardware-key/menu
# contracts and presentation policy are imported from the real remote client.
# Only the scene sampling/model/resource owner differs from its legacy route.
def frame_description(sample:GS.Sample,config:Config) -> IO(Unit):
  GS.Sample{identity,tick,revision,origin,Pixels.Camera{x,y,z,yaw,pitch},cells} = sample
  IO.print("catalog.frame|" ++ Nat.show(config_serial(config)) ++ "|" ++ identity ++ "|" ++ Nat.show(tick) ++ "|" ++
    Nat.show(revision) ++ "|" ++ Nat.show(List.length(&2,GS.Cell,cells)))

def closing(window:Window,assets:Session.Session,link:P.Link,code:U32,message:String) -> IO(Unit):
  do IO<Unit>:
    Window.close(window)
    Session.close(assets)
    P.release_close(link)
    IO.die(Unit,code,message)

def advance(config:Config) -> Config:
  Config{P.Config{human,frames,width,height,trace,serial,+plan,started,menu,keys,physical_keys,cooking},tail} = config
  Config{P.Config{human,Common.remaining(frames),width,height,trace,1n+serial,plan,started,menu,keys,physical_keys,cooking},tail}

def scheduled(window:Window,assets:Session.Session,link:P.Link,config:Config,captured:Bool,keep:Bool,
    resume:Window -> Session.Session -> P.Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  match keep:
    case False{}: closing(window,assets,link,0,"client closed")
    case True{}:
      do IO<Unit>:
        IO.sleep(8)
        resume(window,assets,link,config,captured)

def packet_advance(window:Window,assets:Session.Session,link:P.Link,+next:Config,captured:Bool,keep:Bool,
    resume:Window -> Session.Session -> P.Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  scheduled(window,assets,link,next,captured,keep && Common.continuing(config_frames(next)),resume)

def commands_sent(assets:Session.Session,+config:Config,captured:Bool,result:P.GameResult,
    resume:Window -> Session.Session -> P.Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  match result:
    case P.GameResult{window,link,+native,keep,Done{unit}}:
      +next = with_native(config,native)
      packet_advance(window,assets,link,advance(next),captured && CookingInput.capture_allowed(config_cooking(next)),keep,resume)
    case P.GameResult{window,link,native,keep,Fail{message}}: closing(window,assets,link,1,"game command: " ++ message)

def packet_sent(window:Window,assets:Session.Session,+config:Config,captured:Bool,keep:Bool,commands:List<&2,Wire.Command>,
    result:P.Link & Result<&2,&2,String,Wire.Reply>,resume:Window -> Session.Session -> P.Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  (link,status) = result
  match status:
    case Done{Wire.Ack{epoch,sequence}}:
      do IO<Unit>:
        sent:P.GameResult <- P.send_game_commands(commands,window,link,native_config(config),keep)
        commands_sent(assets,config,captured,sent,resume)
    case Done{other}: closing(window,assets,link,1,"input: Wire:ExpectedAck")
    case Fail{message}: closing(window,assets,link,1,"input: " ++ message)

def packet_flags(assets:Session.Session,link:P.Link,config:Config,old:Bool,previous_capture:Bool,keep:Bool,actions:List<&2,Controls.Action>,
    window:Window,+focused:Bool,+captured:Bool,resume:Window -> Session.Session -> P.Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  +packet = {Controls.Packet{List.reverse(&2,Controls.Action,
    Common.lost_actions(actions,old && Bool.not(focused && captured))),focused,captured}:Controls.Packet}
  do IO<Unit>:
    sent : P.Link & Result<&2,&2,String,Wire.Reply> <- P.call(link,Wire.Input{packet})
    packet_sent(window,assets,config,focused && captured,keep,HUD.packet_commands(packet,previous_capture),sent,resume)

def packet_final(assets:Session.Session,link:P.Link,config:Config,old:Bool,previous_capture:Bool,keep:Bool,actions:List<&2,Controls.Action>,
    result:Window & Bool & Bool,resume:Window -> Session.Session -> P.Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  (window,focused,captured) = result
  packet_flags(assets,link,config,old,previous_capture,keep,actions,window,focused,captured,resume)

def packet_events(assets:Session.Session,link:P.Link,config:Config,previous_capture:Bool,result:Window & Bool & Bool & List<&2,Controls.Action>,
    resume:Window -> Session.Session -> P.Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  (window,captured,keep,actions) = result
  do IO<Unit>:
    status : Window & Bool & Bool <- Input.Native.status(window)
    packet_final(assets,link,config,captured,previous_capture,keep,actions,status,resume)

def packet_initial_flags(assets:Session.Session,link:P.Link,config:Config,pending:List<Event>,allow:Bool,old:Bool,
    window:Window,+focused:Bool,+captured:Bool,resume:Window -> Session.Session -> P.Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    events : Window & Bool & Bool & List<&2,Controls.Action> <- Common.events(pending,window,allow,focused && captured,True{},Common.lost_actions([],old && Bool.not(focused && captured)))
    packet_events(assets,link,config,focused && captured,events,resume)

def packet_initial(assets:Session.Session,link:P.Link,config:Config,pending:List<Event>,allow:Bool,old:Bool,
    result:Window & Bool & Bool,resume:Window -> Session.Session -> P.Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  (window,focused,captured) = result
  packet_initial_flags(assets,link,config,pending,allow,old,window,focused,captured,resume)


def menu_events_sent(assets:Session.Session,+config:Config,pending:List<Event>,old:Bool,result:P.MenuResult,
    resume:Window -> Session.Session -> P.Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  match result:
    case P.MenuResult{window,link,state,False{},Done{unit}}: closing(window,assets,link,0,"client closed")
    case P.MenuResult{window,link,+state,True{},Done{unit}}:
      +next = with_menu(config,state)
      allow = config_human(next) && MenuInput.capture_allowed(state) && CookingInput.capture_allowed(config_cooking(next))
      do IO<Unit>:
        status : Window & Bool & Bool <- Input.Native.status(window)
        packet_initial(assets,link,next,pending,allow,old,status,resume)
    case P.MenuResult{window,link,state,keep,Fail{message}}: closing(window,assets,link,1,"menu command: " ++ message)

def menu_intercepted(assets:Session.Session,link:P.Link,+config:Config,old:Bool,window:Window,
    batch:MenuInput.Batch,resume:Window -> Session.Session -> P.Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  MenuInput.Batch{state,intents,events} = batch
  pending = MenuInput.game_events(events)
  do IO<Unit>:
    sent : P.MenuResult <- P.send_menu_intents(intents,window,link,state,config_human(config),True{})
    menu_events_sent(assets,config,pending,old,sent,resume)

def cooking_after_open(assets:Session.Session,link:P.Link,+config:Config,pending:List<Event>,old:Bool,window:Window,focused:Bool,captured:Bool,opened:Bool,
    resume:Window -> Session.Session -> P.Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  match opened:
    case False{}: menu_intercepted(assets,link,config,old,window,config_menu_batch(config,pending,focused,captured),resume)
    case True{}: packet_initial(assets,link,config,pending,False{},old,(window,focused,captured),resume)

def cooking_after_status(assets:Session.Session,link:P.Link,+config:Config,pending:List<Event>,old:Bool,result:Window & Bool & Bool,
    resume:Window -> Session.Session -> P.Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  (window,focused,captured) = result
  cooking_after_open(assets,link,config,pending,old,window,focused,captured,CookingInput.is_open(config_cooking(config)),resume)

def cooking_events_sent(assets:Session.Session,+config:Config,pending:List<Event>,old:Bool,result:P.CookingResult,
    resume:Window -> Session.Session -> P.Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  match result:
    case P.CookingResult{window,link,state,False{},Done{unit}}: closing(window,assets,link,0,"client closed")
    case P.CookingResult{window,link,state,True{},Done{unit}}:
      +next = with_cooking(config,state)
      do IO<Unit>:
        status:Window & Bool & Bool <- Input.Native.status(window)
        cooking_after_status(assets,link,next,pending,old,status,resume)
    case P.CookingResult{window,link,state,keep,Fail{message}}: closing(window,assets,link,1,"cooking command: " ++ message)

def cooking_intercepted(assets:Session.Session,link:P.Link,+config:Config,old:Bool,window:Window,batch:CookingInput.Batch,
    resume:Window -> Session.Session -> P.Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  CookingInput.Batch{state,intents,events} = batch
  do IO<Unit>:
    sent:P.CookingResult <- P.send_cooking_intents(intents,window,link,state,config_human(config),True{})
    cooking_events_sent(assets,config,MenuInput.game_events(events),old,sent,resume)

def menu_intercept(assets:Session.Session,link:P.Link,+config:Config,pending:List<Event>,old:Bool,
    result:Window & Bool & Bool,resume:Window -> Session.Session -> P.Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  (window,focused,captured) = result
  cooking_intercepted(assets,link,config,old,window,config_cooking_batch(config,pending,focused,captured),resume)

def input_presented(window:Window,assets:Session.Session,link:P.Link,+config:Config,captured:Bool,+image:Image,pending:List<Event>,
    resume:Window -> Session.Session -> P.Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  human = config_human(config)
  events = config_events(config,pending)
  do IO<Unit>:
    P.image_description(image,native_config(config))
    window : Window <- Common.window_policy(window,human)
    status : Window & Bool & Bool <- Input.Native.status(window)
    menu_intercept(assets,link,config,events,captured,status,resume)

def traced(window:Window,assets:Session.Session,link:P.Link,config:Config,captured:Bool,image:Image,pending:List<Event>,
    status:Result<&2,&2,String,Unit>,resume:Window -> Session.Session -> P.Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  match status:
    case Fail{message}: closing(window,assets,link,1,message)
    case Done{unit}: input_presented(window,assets,link,config,captured,image,pending,resume)

def presented(assets:Session.Session,link:P.Link,+config:Config,captured:Bool,result:Window & Image & List<Event>,
    resume:Window -> Session.Session -> P.Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  (window,+image,pending) = result
  do IO<Unit>:
    now : U32 <- NativePresentation.Native.milliseconds()
    IO.print("client.timing|" ++ Nat.show(config_serial(config)) ++ "|" ++ U32.show(U32.sub(now,config_started(config))))
    status : Result<&2,&2,String,Unit> <- P.trace(image,native_config(config))
    traced(window,assets,link,config,captured,image,pending,status,resume)

def cooking_drawn(window:Window,link:P.Link,config:Config,captured:Bool,result:Session.Session & Image,
    resume:Window -> Session.Session -> P.Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  (assets,image) = result
  do IO<Unit>:
    shown:Window & Image & List<Event> <- Window.frame(window,image)
    presented(assets,link,config,captured,shown,resume)

def asset_cooking_overlay(assets:CW.Assets,image:Image,+cooking:CookingInput.State,viewport:Presentation.Viewport) -> CW.Assets & Image:
  CW.Assets{Pixels.Assets{+textures},Catalog.Catalog{identity,entries,
    Resources.Catalog{roots,source,models,+sprites,context,usage}},count} = assets
  +icons = HUD.icons(textures,sprites)
  (CW.Assets{Pixels.Assets{textures},Catalog.Catalog{identity,entries,Resources.Catalog{roots,source,models,sprites,context,usage}},count},
    CookingInput.draw(image,cooking,CookingInput.view(cooking,[],icons),viewport))

def cooking_owned(value:CW.Assets & Image,owner:Demand.Owner,config:Session.Config) -> Session.Session & Image:
  (assets,image) = value
  (Session.Session{owner,assets,config},image)

def cooking_overlay(image:Image,+config:Config,session:Session.Session) -> Session.Session & Image:
  Session.Session{owner,assets,policy} = session
  cooking_owned(asset_cooking_overlay(assets,image,config_cooking(config),Presentation.hud_viewport(config_plan(config))),owner,policy)

def drawn(window:Window,link:P.Link,+config:Config,captured:Bool,view:HUD.View,screen:Maybe<&2,Screen.View>,result:Session.Session & Result<&2,&2,String,Image>,
    resume:Window -> Session.Session -> P.Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  (assets,status) = result
  match status:
    case Fail{message}: closing(window,assets,link,1,"render: " ++ message)
    case Done{image}: cooking_drawn(window,link,config,captured,cooking_overlay(config_image(config,image,view,screen),config,assets),resume)

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

def cooking_views(assets:Session.Session,snapshot:CookingMenu.Snapshot) -> Session.Session & Result<&2,&1,String,HUD.View & Maybe<&2,Screen.View>>:
  CookingMenu.Snapshot{handle,furnace,Inventory.MenuSnapshot{Inventory.Persisted{main,equipment,status},craft,carried,result,opened,revision}} = snapshot
  PNG.paired(Session.Session,HUD.View,Session.Session & Result<&2,&1,String,HUD.View & Maybe<&2,Screen.View>>,hud_view(assets,main),
    actual => view => (actual,Done{(view,None{})}))

def inventory_timed(window:Window,assets:Session.Session,link:P.Link,+config:Config,captured:Bool,+sample:GS.Sample,
    view:HUD.View,screen:Maybe<&2,Screen.View>,begin:U32,
    resume:Window -> Session.Session -> P.Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  +timed = with_started(config,begin)
  do IO<Unit>:
    frame_description(sample,timed)
    drawn(window,link,timed,captured,view,screen,Session.draw(sample,assets,config_width(timed),config_height(timed)),resume)

def inventory_draw(window:Window,link:P.Link,+config:Config,captured:Bool,+sample:GS.Sample,
    prepared:Session.Session & Result<&2,&1,String,HUD.View & Maybe<&2,Screen.View>>,resume:Window -> Session.Session -> P.Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  (assets,status) = prepared
  match status:
    case Fail{message}: closing(window,assets,link,1,message)
    case Done{Tuple{view,screen}}:
      do IO<Unit>:
        begin : U32 <- NativePresentation.Native.milliseconds()
        inventory_timed(window,assets,link,config,captured,sample,view,screen,begin,resume)

def cooking_inventory_opened(window:Window,assets:Session.Session,+config:Config,captured:Bool,sample:GS.Sample,
    snapshot:CookingMenu.Snapshot,link:P.Link,opened:Bool,
    resume:Window -> Session.Session -> P.Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  match snapshot opened:
    case _ True{}: inventory_draw(window,link,config,captured,sample,cooking_views(assets,snapshot),resume)
    case CookingMenu.Snapshot{handle,furnace,inventory} False{}:
      +menu = MenuInput.observed(config_menu(config),inventory)
      inventory_draw(window,link,with_menu(config,menu),captured,sample,menu_views(assets,menu),resume)

def cooking_inventory_authority(window:Window,assets:Session.Session,+config:Config,captured:Bool,sample:GS.Sample,link:P.Link,
    authority:Maybe<&2,CookingMenu.Snapshot>,
    resume:Window -> Session.Session -> P.Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  match authority:
    case None{}: closing(window,assets,link,1,"cooking query: missing authoritative snapshot")
    case Some{snapshot}: cooking_inventory_opened(window,assets,config,captured,sample,snapshot,link,CookingInput.is_open(config_cooking(config)),resume)

def cooking_inventory_status(assets:Session.Session,link:P.Link,+config:Config,sample:GS.Sample,result:Window & Bool & Bool,
    resume:Window -> Session.Session -> P.Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  (window,focused,captured) = result
  cooking_inventory_authority(window,assets,config,focused && captured,sample,link,CookingInput.authority(config_cooking(config)),resume)

def cooking_inventory_finished(assets:Session.Session,+config:Config,sample:GS.Sample,result:P.CookingResult,
    resume:Window -> Session.Session -> P.Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  match result:
    case P.CookingResult{window,link,state,False{},Done{unit}}: closing(window,assets,link,0,"client closed")
    case P.CookingResult{window,link,state,True{},Done{unit}}:
      +next = with_cooking(config,state)
      do IO<Unit>:
        status:Window & Bool & Bool <- Input.Native.status(window)
        cooking_inventory_status(assets,link,next,sample,status,resume)
    case P.CookingResult{window,link,state,keep,Fail{message}}: closing(window,assets,link,1,"cooking query: " ++ message)

def cooking_inventory_updated(window:Window,assets:Session.Session,link:P.Link,+config:Config,sample:GS.Sample,
    value:CookingInput.State & List<&2,CookingScreen.Intent>,
    resume:Window -> Session.Session -> P.Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  (next,intents) = value
  do IO<Unit>:
    result:P.CookingResult <- P.send_cooking_intents(intents,window,link,next,config_human(config),True{})
    cooking_inventory_finished(assets,config,sample,result,resume)

def cooking_inventoried(window:Window,assets:Session.Session,link:P.Link,+config:Config,sample:GS.Sample,reply:CookingMenu.Reply,
    resume:Window -> Session.Session -> P.Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  cooking_inventory_updated(window,assets,link,config,sample,CookingInput.completed(config_cooking(config),reply),resume)

def inventoried(window:Window,assets:Session.Session,+config:Config,captured:Bool,sample:GS.Sample,
    result:P.Link & Result<&2,&2,String,Wire.Reply>,resume:Window -> Session.Session -> P.Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  (link,status) = result
  match status:
    case Done{Wire.CookingReply{epoch,sequence,accepted,message,snapshot}}:
      cooking_inventoried(window,assets,link,config,sample,CookingMenu.Reply{accepted,message,snapshot,[]},resume)
    case Done{Wire.MenuReply{epoch,sequence,accepted,message,snapshot}}:
      +menu = MenuInput.observed(config_menu(config),snapshot)
      inventory_draw(window,link,with_menu(config,menu),captured,sample,menu_views(assets,menu),resume)
    case Done{other}: closing(window,assets,link,1,"inventory query: Wire:ExpectedMenu")
    case Fail{message}: closing(window,assets,link,1,"inventory query: " ++ message)

def resources_ready(window:Window,link:P.Link,+config:Config,captured:Bool,sample:GS.Sample,
    result:Session.Session & Result<&2,&2,Catalog.Error,Unit>,
    resume:Window -> Session.Session -> P.Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  (assets,status) = result
  match status:
    case Fail{error}: closing(window,assets,link,1,"resource demand: " ++ Draw.error_text(error))
    case Done{unit}:
      do IO<Unit>:
        reply : P.Link & Result<&2,&2,String,Wire.Reply> <- P.call(link,P.inspect_command(config_cooking(config)))
        inventoried(window,assets,config,captured,sample,reply,resume)

def resources_linked(window:Window,+config:Config,captured:Bool,sample:GS.Sample,
    value:P.Link & (Session.Session & Result<&2,&2,Catalog.Error,Unit>),
    resume:Window -> Session.Session -> P.Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  (link,result) = value
  resources_ready(window,link,config,captured,sample,result,resume)

def resources_prepared(window:Window,link:P.Link,+config:Config,captured:Bool,sample:GS.Sample,
    prepared:Session.Preparation,resume:Window -> Session.Session -> P.Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  match prepared:
    case Session.Ready{result}: resources_ready(window,link,config,captured,sample,result,resume)
    case Session.Pending{missing,owner,catalog,error}:
      do IO<Unit>:
        value:P.Link & (Session.Session & Result<&2,&2,Catalog.Error,Unit>) <-
          ResourceTransport.load(link,Session.Pending{missing,owner,catalog,error},config_width(config),config_height(config))
        resources_linked(window,config,captured,sample,value,resume)

def snapshot_ready(window:Window,assets:Session.Session,link:P.Link,config:Config,captured:Bool,+sample:GS.Sample,
    resume:Window -> Session.Session -> P.Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  resources_prepared(window,link,config,captured,sample,Session.prepare(sample,assets),resume)

def sampled(window:Window,assets:Session.Session,config:Config,captured:Bool,result:P.Link & Result<&2,&2,String,Wire.Reply>,
    resume:Window -> Session.Session -> P.Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  (link,status) = result
  match status:
    case Fail{message}: closing(window,assets,link,1,"frame query: " ++ message)
    case Done{Wire.CatalogFrameReply{epoch,sequence,sample}}: snapshot_ready(window,assets,link,config,captured,sample,resume)
    case Done{other}: closing(window,assets,link,1,"frame query: Wire:ExpectedFrame")

def query_planned(window:Window,assets:Session.Session,link:P.Link,+config:Config,captured:Bool,valid:Bool,
    resume:Window -> Session.Session -> P.Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  match valid:
    case False{}: closing(window,assets,link,1,"drawable dimensions exceed the configured presentation allocation policy")
    case True{}:
      do IO<Unit>:
        reply : P.Link & Result<&2,&2,String,Wire.Reply> <- P.call(link,Wire.FrameCatalog{config_width(config),config_height(config)})
        sampled(window,assets,config,captured,reply,resume)

def planned(assets:Session.Session,link:P.Link,+config:Config,captured:Bool,
    result:Window & Presentation.Geometry,resume:Window -> Session.Session -> P.Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  (actual,+geometry) = result
  +next = with_geometry(config,geometry)
  query_planned(actual,assets,link,next,captured,
    Presentation.geometry_valid(geometry) &&
      Presentation.dimensions(Presentation.output_width(config_plan(next)),Presentation.output_height(config_plan(next))),resume)

@unsafe
def loop(window:Window,assets:Session.Session,link:P.Link,+config:Config,captured:Bool) -> IO(Unit):
  do IO<Unit>:
    actual : Window & Presentation.Geometry <- NativePresentation.measure(window)
    planned(assets,link,config,captured,actual,w => a => l => c => capture => loop(w,a,l,c,capture))

def starting_frames(window:Window,assets:Session.Session,link:P.Link,+config:Config,captured:Bool,sample:GS.Sample,frames:Maybe<&2,Nat>) -> IO(Unit):
  match frames:
    case Some{0n}: closing(window,assets,link,0,"client closed")
    case _: snapshot_ready(window,assets,link,config,captured,sample,w => a => l => c => capture => loop(w,a,l,c,capture))

def starting(window:Window,assets:Session.Session,link:P.Link,+config:Config,captured:Bool,sample:GS.Sample) -> IO(Unit):
  starting_frames(window,assets,link,config,captured,sample,config_frames(config))

def captured(assets:Session.Session,link:P.Link,config:Config,sample:GS.Sample,result:Window & Bool) -> IO(Unit):
  (window,capture) = result
  starting(window,assets,link,config,capture,sample)

def capture_configured(window:Window,assets:Session.Session,link:P.Link,+config:Config,sample:GS.Sample,valid:Bool) -> IO(Unit):
  match valid:
    case False{}: closing(window,assets,link,1,"drawable/content dimensions exceed the configured presentation allocation policy")
    case True{}:
      do IO<Unit>:
        actual : Window & Bool <- Input.capture(window,config_human(config))
        captured(assets,link,config,sample,actual)

def configured_window(assets:Session.Session,link:P.Link,+config:Config,sample:GS.Sample,
    actual:Window & Presentation.Geometry) -> IO(Unit):
  (window,+geometry) = actual
  +next = with_geometry(config,geometry)
  capture_configured(window,assets,link,next,sample,Presentation.geometry_valid(geometry) &&
    Presentation.dimensions(Presentation.output_width(config_plan(next)),Presentation.output_height(config_plan(next))))

def keys_enabled(assets:Session.Session,link:P.Link,config:Config,sample:GS.Sample,result:Window & Bool) -> IO(Unit):
  (window,enabled) = result
  next = with_physical_keys(config,enabled)
  do IO<Unit>:
    actual : Window & Presentation.Geometry <- NativePresentation.measure(window)
    configured_window(assets,link,next,sample,actual)

def opened_settings(assets:Session.Session,link:P.Link,+config:Config,sample:GS.Sample,settings:Presentation.Settings,result:Result<&1,&1,U32 & String,Window>) -> IO(Unit):
  Presentation.Settings{+ow,+oh,percent,scale,+native,+fullscreen} = settings
  match result:
    case Fail{(code,message)}:
      do IO<Unit>:
        Session.close(assets)
        P.release_close(link)
        IO.die(Unit,code,"window open: " ++ message)
    case Done{window}:
      do IO<Unit>:
        configured : Window <- NativePresentation.Native.configure(window,ow,oh,native,fullscreen,config_human(config))
        keyed : Window & Bool <- NativePresentation.Native.inventory_keys(configured)
        keys_enabled(assets,link,config,sample,keyed)

def opened(assets:Session.Session,link:P.Link,+config:Config,sample:GS.Sample,result:Result<&1,&1,U32 & String,Window>) -> IO(Unit):
  opened_settings(assets,link,config,sample,config_settings(config),result)

def open_catalogued_valid(assets:Session.Session,link:P.Link,sample:GS.Sample,+human:Bool,frames:Maybe<&2,Nat>,+settings:Presentation.Settings,catalog:ItemDefinitions.Catalog,keys:Keys.Profile) -> IO(Unit):
  Presentation.Settings{+ow,+oh,percent,scale,native,fullscreen} = settings
  +plan = Presentation.plan(settings,Presentation.Geometry{ow,oh,ow,oh},human)
  do IO<Unit>:
    mode : Result<&1,&1,U32 & String,String> <- IO.get_env("BEND_MINECRAFT_FRAME_DIR")
    window : Result<&1,&1,U32 & String,Window> <- Window.open("Minecraft 26.3 — remote LocalPlayer resource client",
      PNG.choose(U32,960,PNG.choose(U32,512,ow,U32.is_eq(ow,128) && U32.is_eq(oh,128)),human),
      PNG.choose(U32,540,PNG.choose(U32,512,oh,U32.is_eq(ow,128) && U32.is_eq(oh,128)),human))
    opened(assets,link,Config{P.Config{human,frames,Presentation.scene_width(plan),Presentation.scene_height(plan),P.trace_mode(mode),0n,plan,0,MenuInput.new(catalog),keys,False{},CookingInput.new()},[]},sample,window)

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
