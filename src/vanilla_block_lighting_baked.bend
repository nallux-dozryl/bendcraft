import Base
import ./block_bake.bend as K
import ./block_model.bend as B
import ./mesh_render.bend as Mesh
import ./vanilla_block_lighting_model.bend as M
import ./vanilla_block_lighting.bend as L

def position(vertex:Mesh.Vertex) -> B.Vec3:
  Mesh.Vertex{Mesh.Vec3{x,y,z},uv}=vertex
  B.Vec3{x,y,z}
def quad(value:K.Baked) -> M.Quad:
  K.Baked{a,b,c,d,direction,cull,sprite,texture,tint,emission,override,layer,force,animated,default_shade,nether_shade}=value
  M.Quad{position(a),position(b),position(c),position(d),direction,override,emission}
# Geometry selection and tint/culling stay with their actual loaded catalog.
# first_part_ao is from the FIRST collected model part, even for later parts.
def request(stamp:M.Stamp,origin:M.Position,+source:M.StateInfo,baked:K.Baked,ambient_option:Bool,first_part_ao:Bool,known_flat:Maybe<&2,U32>) -> M.Request:
  M.StateInfo{id,+emission,r,s,f,p,h}=source
  M.Request{stamp,origin,source,quad(baked),L.mode(ambient_option,first_part_ao,emission,known_flat)}
