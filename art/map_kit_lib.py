
import bpy, bmesh, random, math
from mathutils import Vector, Matrix
def hx(h):
    c=[int(h[i:i+2],16)/255 for i in (0,2,4)]
    return tuple(((x/12.92) if x<=0.04045 else ((x+0.055)/1.055)**2.4) for x in c)+(1,)
PAL={'StoneLight':'C8D3A0','StoneMoss':'9DB27A','StoneShadow':'6E8558','PathSand':'E3C79A','PathTan':'C9A36B',
'WoodPlank':'B5773D','Rope':'8A6A3E','Trunk':'6B4A2B','CanopyBright':'8CC63F','CanopyMid':'4E9A2E','CanopyDeep':'2E5E26',
'Tar':'2B2118','TarBubble':'4A3A2A','UiDanger':'E2483D','Gem':'8FF3FF','GemGlint':'E8FDFF','Cliff':'7E9A5E','Soil':'3E3024','Water':'3CC2C8','UiGold':'F5B83D'}
def mat(name):
    m=bpy.data.materials.get('JJ_'+name)
    if m: return m
    m=bpy.data.materials.new('JJ_'+name); m.use_nodes=True
    b=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    b.inputs['Base Color'].default_value=hx(PAL[name]); b.inputs['Roughness'].default_value=0.85
    m.diffuse_color=hx(PAL[name]); return m
def coll(name, parent=None):
    c=bpy.data.collections.get(name)
    if not c:
        c=bpy.data.collections.new(name); (parent or bpy.context.scene.collection).children.link(c)
    return c
class Acc:
    """accumulates geometry per material, then emits one object per material"""
    def __init__(s,name,col): s.name=name; s.col=col; s.bms={}
    def bm(s,m):
        if m not in s.bms: s.bms[m]=bmesh.new()
        return s.bms[m]
    def box(s,m,center,size,rot=(0,0,0),bevel=0.0,jit=0.0,seg=1,rng=None):
        bm=bmesh.new(); bmesh.ops.create_cube(bm,size=1.0)
        for v in bm.verts: v.co=Vector((v.co.x*size[0],v.co.y*size[1],v.co.z*size[2]))
        if bevel>0:
            bmesh.ops.bevel(bm,geom=list(bm.edges),offset=min(bevel,min(size)*0.45),segments=seg,affect='EDGES',profile=0.5)
        if jit and rng:
            for v in bm.verts: v.co+=Vector((rng.uniform(-jit,jit),rng.uniform(-jit,jit),rng.uniform(-jit,jit)))
        M=Matrix.Translation(Vector(center))@Matrix.Rotation(rot[2],4,'Z')@Matrix.Rotation(rot[1],4,'Y')@Matrix.Rotation(rot[0],4,'X')
        bmesh.ops.transform(bm,matrix=M,verts=bm.verts)
        s._merge(m,bm)
    def cyl(s,m,a,b,r,n=10,cap=True,r2=None,jit=0,rng=None):
        bm=bmesh.new(); r2=r if r2 is None else r2
        a=Vector(a); b=Vector(b); d=b-a; L=d.length
        bmesh.ops.create_cone(bm,cap_ends=cap,segments=n,radius1=r,radius2=r2,depth=L)
        if jit and rng:
            for v in bm.verts: v.co+=Vector((rng.uniform(-jit,jit),rng.uniform(-jit,jit),0))
        q=Vector((0,0,1)).rotation_difference(d.normalized())
        M=Matrix.Translation((a+b)/2)@q.to_matrix().to_4x4()
        bmesh.ops.transform(bm,matrix=M,verts=bm.verts); s._merge(m,bm)
    def ico(s,m,c,r,sc=(1,1,1),sub=1,jit=0,rng=None):
        bm=bmesh.new(); bmesh.ops.create_icosphere(bm,subdivisions=sub,radius=r)
        for v in bm.verts:
            v.co=Vector((v.co.x*sc[0],v.co.y*sc[1],v.co.z*sc[2]))
            if jit and rng: v.co*=1+rng.uniform(-jit,jit)
        bmesh.ops.translate(bm,vec=Vector(c),verts=bm.verts); s._merge(m,bm)
    def raw(s,m,verts,faces):
        bm=bmesh.new(); vs=[bm.verts.new(v) for v in verts]
        for f in faces: bm.faces.new([vs[i] for i in f])
        s._merge(m,bm)
    def _merge(s,m,src):
        me=bpy.data.meshes.new('t'); src.to_mesh(me); src.free()
        s.bm(m).from_mesh(me); bpy.data.meshes.remove(me)
    def done(s,loc=(0,0,0)):
        objs=[]
        for m,bm in s.bms.items():
            me=bpy.data.meshes.new(s.name+'_'+m); bm.normal_update(); bm.to_mesh(me); bm.free()
            me.materials.append(mat(m))
            for p in me.polygons: p.use_smooth=False
            o=bpy.data.objects.new(s.name+'_'+m,me); s.col.objects.link(o); o.location=loc; objs.append(o)
        return objs
def clear(colname):
    c=bpy.data.collections.get(colname)
    if c:
        for o in list(c.all_objects): bpy.data.objects.remove(o)
W=24; HALF=12
# flagstone floor: irregular cut stones filling x in [x0,x1], y in [y0,y1], top at z
def flagstones(A,rng,x0,x1,y0,y1,z=0,mats=('PathSand','PathTan'),row=(3.0,5.0),col=(3.0,6.0),thick=1.0,base='Soil',moss=0.0):
    A.box(base,((x0+x1)/2,(y0+y1)/2,z-0.35-thick/2),(x1-x0,y1-y0,thick))
    y=y0
    while y<y1-0.01:
        h=min(rng.uniform(*row),y1-y)
        if y1-(y+h)<1.5: h=y1-y
        x=x0+ (rng.uniform(0,col[0]) if rng.random()<0.5 else 0)
        # first partial stone
        xs=[x0]
        while x<x1-0.01:
            if x>x0: xs.append(x)
            x+=rng.uniform(*col)
        xs.append(x1)
        for i in range(len(xs)-1):
            a,b=xs[i],xs[i+1]
            if b-a<0.6: continue
            m=mats[0] if rng.random()<0.65 else mats[1]
            if moss and rng.random()<moss: m='StoneMoss'
            dz=rng.uniform(-0.08,0.12)
            A.box(m,((a+b)/2,y+h/2,z-0.4+dz),(b-a-0.22,h-0.22,0.8),rot=(0,0,rng.uniform(-0.015,0.015)),bevel=0.18,jit=0.04,rng=rng)
        y+=h
def kerbs(A,rng,y0,y1,z=0):
    for sx in (-1,1):
        y=y0
        while y<y1-0.01:
            l=min(rng.uniform(3.5,6),y1-y)
            if y1-(y+l)<1.2: l=y1-y
            A.box('PathTan',(sx*(HALF-0.75),y+l/2,z+0.05),(1.5,l-0.12,0.9),bevel=0.2,jit=0.03,rng=rng)
            y+=l
def foundation(A,rng,y0,y1,z=-1.0,depth=14):
    # ashlar courses on both faces, a core box behind them
    A.box('StoneShadow',(0,(y0+y1)/2,z-depth/2),(W-2.2,y1-y0-0.1,depth))
    for sx in (-1,1):
        zz=z; k=0
        while zz>z-depth+0.5:
            ch=rng.uniform(1.8,2.6); y=y0-(rng.uniform(0,2) if k%2 else 0)
            while y<y1-0.3:
                l=rng.uniform(2.8,5.0); a=max(y,y0); b=min(y+l,y1)
                if b-a>0.6:
                    m='StoneMoss' if (k==0 and rng.random()<0.6) or rng.random()<0.15 else ('StoneShadow' if rng.random()<0.7 else 'Cliff')
                    A.box(m,(sx*(HALF-0.9),(a+b)/2,zz-ch/2),(1.6,b-a-0.18,ch-0.18),bevel=0.22,jit=0.05,rng=rng)
                y+=l
            zz-=ch; k+=1
        mossdrape(A,rng,sx*(HALF+0.05),y0,y1,z+0.1,sx)
def mossdrape(A,rng,x,y0,y1,z,side):
    # mossy lip hanging over a stone edge
    y=y0
    while y<y1:
        l=rng.uniform(1.5,3.5)
        if rng.random()<0.55:
            A.box('CanopyMid',(x,y+l/2,z-rng.uniform(0.2,0.9)/2),(0.35,l,rng.uniform(0.4,1.4)),bevel=0.12,jit=0.05,rng=rng)
        y+=l

def view(loc,target,lens=35):
    for a in bpy.context.screen.areas:
        if a.type=='VIEW_3D':
            sp=a.spaces.active; r=sp.region_3d
            d=Vector(target)-Vector(loc)
            r.view_perspective='PERSP'; r.view_location=Vector(target)
            r.view_rotation=d.to_track_quat('-Z','Y'); r.view_distance=d.length; sp.lens=lens
            sp.shading.type='MATERIAL'; sp.overlay.show_floor=False; sp.overlay.show_axis_x=False; sp.overlay.show_axis_y=False
