import Base
import ./client_render.bend as R
import ./item_entity_render.bend as IR
import ./item_entity_render_model.bend as D

# Camera.setRotation's verified projected radians, then the actual JOML
# rotationYXZ arithmetic at Z=0. Native sinf remains a measured float boundary.
def quaternion(+sx:F32,+cx:F32,+sy:F32,+cy:F32) -> D.Quaternion:
  +a = F32.mul(cy,sx)
  +b = F32.mul(sy,cx)
  +c = F32.mul(sy,sx)
  +d = F32.mul(cy,cx)
  D.Quaternion{F32.add(F32.mul(a,1.0),F32.mul(b,0.0)),
    F32.sub(F32.mul(b,1.0),F32.mul(a,0.0)),
    F32.sub(F32.mul(d,0.0),F32.mul(c,1.0)),
    F32.add(F32.mul(d,1.0),F32.mul(c,0.0))}
def billboard(camera:R.Camera) -> D.Quaternion:
  R.Camera{x,y,z,yaw,pitch} = camera
  +xh = F32.mul(F32.neg(pitch),0.5)
  +yh = F32.mul(F32.sub(3.1415927,yaw),0.5)
  +sx = F32.sin(xh)
  +sy = F32.sin(yh)
  quaternion(sx,IR.cosine(sx,xh),sy,IR.cosine(sy,yh))
