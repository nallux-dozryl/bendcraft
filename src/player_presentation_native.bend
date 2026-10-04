import Base
import ./player_presentation.bend as P

# Effects are separate from the pure policy and its CPU proof/test boundary.
def Native.configure(window:Window,width:U32,height:U32,native:Bool,fullscreen:Bool,human:Bool) -> IO(Window):
  import "./native/player_presentation.c"
  import "./native/player_presentation.js"

def Native.measure(window:Window) -> IO(Window & U32 & U32 & U32 & U32):
  import "./native/player_presentation.c"
  import "./native/player_presentation.js"

def Native.milliseconds() -> IO(U32):
  import "./native/player_presentation.c"
  import "./native/player_presentation.js"

def Native.inventory_keys(window:Window) -> IO(Window & Bool):
  import "./native/player_presentation.c"
  import "./native/player_presentation.js"

def measured(result:Window & U32 & U32 & U32 & U32) -> Window & P.Geometry:
  (window,width,height,point_width,point_height) = result
  (window,P.Geometry{width,height,point_width,point_height})

def measure(window:Window) -> IO(Window & P.Geometry):
  do IO<Window & P.Geometry>:
    value : Window & U32 & U32 & U32 & U32 <- Native.measure(window)
    return measured(value)
