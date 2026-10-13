"""Pillow-compatible vector drawing sink, shared with the canonical renderer."""
from html import escape
from pathlib import Path
from PIL import ImageColor


class VectorDraw:
    def __init__(self, width, height, canvas=None):
        self.canvas = canvas
        self.width, self.height = width, height
        self.svg = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="{width/4}mm" height="{height/4}mm">']
        if canvas:
            canvas.saveState()
            pw,ph=canvas._pagesize
            factor=min(pw/width,ph/height)
            canvas.translate((pw-width*factor)/2,(ph-height*factor)/2)
            canvas.scale(factor,factor)
            canvas.translate(0, height)
            canvas.scale(1, -1)

    @staticmethod
    def color(value):
        if value is None: return None
        return ImageColor.getrgb(value) if isinstance(value, str) else value

    def style(self, fill=None, outline=None, width=1):
        def hexcolor(v):
            return '#%02x%02x%02x' % tuple(self.color(v)[:3]) if v is not None else 'none'
        if self.canvas:
            for color, setter in [(fill,self.canvas.setFillColorRGB),(outline,self.canvas.setStrokeColorRGB)]:
                if color is not None: setter(*(c/255 for c in self.color(color)[:3]))
            self.canvas.setLineWidth(width)
        return f'fill="{hexcolor(fill)}" stroke="{hexcolor(outline)}" stroke-width="{width}"'

    def rectangle(self, xy, fill=None, outline=None, width=1):
        x1,y1,x2,y2=xy;style=self.style(fill,outline,width)
        self.svg.append(f'<rect x="{x1}" y="{y1}" width="{x2-x1}" height="{y2-y1}" {style}/>')
        if self.canvas:self.canvas.rect(x1,y1,x2-x1,y2-y1,fill=int(fill is not None),stroke=int(outline is not None))

    def ellipse(self,xy,fill=None,outline=None,width=1):
        x1,y1,x2,y2=xy;style=self.style(fill,outline,width)
        self.svg.append(f'<ellipse cx="{(x1+x2)/2}" cy="{(y1+y2)/2}" rx="{(x2-x1)/2}" ry="{(y2-y1)/2}" {style}/>')
        if self.canvas:self.canvas.ellipse(x1,y1,x2,y2,fill=int(fill is not None),stroke=int(outline is not None))

    def line(self,xy,fill='black',width=1):
        points=xy if isinstance(xy[0],(tuple,list)) else list(zip(xy[::2],xy[1::2]))
        style=self.style(None,fill,width)
        self.svg.append('<polyline points="'+' '.join(f'{x},{y}' for x,y in points)+f'" {style}/>')
        if self.canvas:
            p=self.canvas.beginPath();p.moveTo(*points[0])
            for point in points[1:]:p.lineTo(*point)
            self.canvas.drawPath(p)

    def text(self,xy,text,font=None,fill='black'):
        x,y=xy;size=getattr(font,'size',14);self.style(fill)
        self.svg.append(f'<text x="{x}" y="{y+size}" font-family="Arial, sans-serif" font-size="{size}" {self.style(fill)}>{escape(str(text))}</text>')
        if self.canvas:
            from reportlab.pdfbase import pdfmetrics
            from reportlab.pdfbase.ttfonts import TTFont
            name='VesselUnicode'
            if name not in pdfmetrics.getRegisteredFontNames():
                path=getattr(font,'path',None)
                if not path or not Path(path).is_file():raise ValueError('Unicode font is required for vessel PDF')
                pdfmetrics.registerFont(TTFont(name,path))
            self.canvas.saveState();self.canvas.translate(x,y);self.canvas.scale(1,-1)
            self.canvas.setFont(name,size);self.canvas.drawString(0,-size,str(text));self.canvas.restoreState()

    def finish(self):
        if self.canvas:self.canvas.restoreState()
        return (''.join(self.svg)+'</svg>').encode('utf-8')

    def begin_entity(self, ident):
        self.svg.append(f'<g data-entity-id="{escape(str(ident),quote=True)}">')

    def end_entity(self):
        self.svg.append('</g>')


def export_pdf(geometry):
    from io import BytesIO
    from reportlab.pdfgen.canvas import Canvas
    from reportlab.lib.units import mm
    from vessel_geometry_v2 import render_v2
    from vessel_sheet import sheet_spec
    spec=sheet_spec(geometry)
    stream=BytesIO();canvas=Canvas(stream,pagesize=(spec['width_mm']*mm,spec['height_mm']*mm),pageCompression=1)
    canvas.setTitle(f"Сосуд • общая схема • ревизия {geometry['revision']}")
    details=[None]+list(dict.fromkeys((geometry.get('print_settings') or {}).get('detail_ids',[])))
    valid={p['id'] for p in geometry['parts']}
    for detail in details:
        if detail is not None and detail not in valid:continue
        render_v2(geometry,spec['width'],spec['height'],detail=detail,vector_canvas=canvas)
        canvas.showPage()
    canvas.save();return stream.getvalue()
