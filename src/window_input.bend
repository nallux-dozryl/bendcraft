import Base

# OS state only; the same affine Base Window is returned. Pinned Base emits no
# focus-loss event and returns no result from Window.grab, so callers need this
# observation to release logical held keys and recognize actual capture.
def Native.status(window:Window) -> IO(Window & Bool & Bool):
  import "./native/window_input.c"
  import "./native/window_input.js"

def focused(result:Window & Bool & Bool) -> Window & Bool:
  (window,focused,captured) = result
  (window,focused && captured)

def capture(window:Window,on:Bool) -> IO(Window & Bool):
  do IO<Window & Bool>:
    window : Window <- Window.grab(window,on)
    status : Window & Bool & Bool <- Native.status(window)
    return focused(status)
