import Base
import ../src/platform.bend as P

def finish(observed: Window & String) -> IO(Unit):
  (window, text) = observed
  do IO<Unit>:
    IO.print("platform_window=" ++ text)
    Window.close(window)
    after : String <- P.Platform.observe()
    IO.print("platform_after=" ++ after)

def after_frame(shown: Window & Image & List<Event>) -> IO(Unit):
  (window, image, events) = shown
  do IO<Unit>:
    observed : Window & String <- P.Platform.inspect(window)
    finish(observed)

def main() -> IO(Unit):
  do IO<Unit>:
    before : String <- P.Platform.observe()
    IO.print("platform_before=" ++ before)
    window : Window <- IO.try(Window, Window.open("Minecraft platform launch probe", 64, 64))
    shown : Window & Image & List<Event> <- Window.frame(window, Pix{2241348})
    IO.print("platform_frame_returned=true")
    after_frame(shown)
