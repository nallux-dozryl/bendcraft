import Base
import ../src/window_input.bend as W
import ../src/platform.bend as P

def reported(status:Window & Bool & Bool,label:String) -> IO(Window):
  (window,focused,captured) = status
  do IO<Window>:
    IO.print(label ++ "=" ++ Bool.show(focused) ++ "," ++ Bool.show(captured))
    return window

def captured(status:Window & Bool) -> IO(Window):
  (window,actual) = status
  do IO<Window>:
    IO.print("capture_result=" ++ Bool.show(actual))
    return window

def framed(shown:Window & Image & List<Event>) -> IO(Window):
  (window,image,events) = shown
  do IO<Window>:
    IO.print("frame_events=" ++ Nat.show(List.length(&1,Event,events)))
    return window

def inspected(status:Window & String) -> IO(Unit):
  (window,text) = status
  do IO<Unit>:
    IO.print("window=" ++ text)
    Window.close(window)

def main() -> IO(Unit):
  do IO<Unit>:
    before : String <- P.Platform.observe()
    IO.print("before=" ++ before)
    window : Window <- IO.try(Window,Window.open("Minecraft input boundary probe",64,64))
    first : Window & Bool & Bool <- W.Native.status(window)
    window : Window <- reported(first,"initial")
    status : Window & Bool <- W.capture(window,True{})
    window : Window <- captured(status)
    second : Window & Bool & Bool <- W.Native.status(window)
    window : Window <- reported(second,"after_capture_attempt")
    shown : Window & Image & List<Event> <- Window.frame(window,Pix{4281558681})
    window : Window <- framed(shown)
    third : Window & Bool & Bool <- W.Native.status(window)
    window : Window <- reported(third,"after_frame")
    observed : Window & String <- P.Platform.inspect(window)
    inspected(observed)
    after : String <- P.Platform.observe()
    IO.print("after=" ++ after)
