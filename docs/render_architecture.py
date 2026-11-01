"""Render the README diagram as SVG and PNG. Requires Pillow: pip install Pillow."""
from pathlib import Path
from html import escape
import os
from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).parent / 'assets'
OUT.mkdir(exist_ok=True)
W, H = 1600, 1030
im = Image.new('RGB', (W, H), '#f5f8fc')
draw = ImageDraw.Draw(im)
font_path = os.environ.get('DIAGRAM_FONT', 'C:/Windows/Fonts/msyh.ttc')
bold_path = os.environ.get('DIAGRAM_FONT_BOLD', 'C:/Windows/Fonts/msyhbd.ttc')
svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" role="img" aria-labelledby="title desc">',
       '<title id="title">视觉识别质检与控制描摹系统架构</title>',
       '<desc id="desc">主板采集并显示图像，通过以太网向副板传图；副板完成识别与路径规划，经串口无线桥接连接 GRBL 写字机。</desc>',
       '<rect width="1600" height="1030" fill="#f5f8fc"/>']

def text(x, y, value, size=24, color='#334155', bold=False):
    font = ImageFont.truetype(bold_path if bold else font_path, size)
    draw.text((x, y), value, font=font, fill=color, anchor='lt')
    svg.append(f'<text x="{x}" y="{y+size}" font-family="Microsoft YaHei,Noto Sans CJK SC,sans-serif" font-size="{size}" font-weight="{700 if bold else 400}" fill="{color}">{escape(value)}</text>')

def rect(box, fill, stroke='#d6dfeb', radius=18):
    x0, y0, x1, y1 = box
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=stroke, width=2)
    svg.append(f'<rect x="{x0}" y="{y0}" width="{x1-x0}" height="{y1-y0}" rx="{radius}" fill="{fill}" stroke="{stroke}" stroke-width="2"/>')

def arrow(points, color='#64748b', double=False):
    draw.line(points, fill=color, width=4)
    svg.append('<polyline points="' + ' '.join(f'{x},{y}' for x, y in points) + f'" fill="none" stroke="{color}" stroke-width="4" stroke-linejoin="round"/>')
    def head(a, b):
        from math import hypot
        dx, dy = b[0]-a[0], b[1]-a[1]
        n = hypot(dx, dy); ux, uy = dx/n, dy/n
        p = [b, (b[0]-14*ux+7*uy, b[1]-14*uy-7*ux), (b[0]-14*ux-7*uy, b[1]-14*uy+7*ux)]
        draw.polygon(p, fill=color)
        svg.append('<polygon points="' + ' '.join(f'{x:.1f},{y:.1f}' for x, y in p) + f'" fill="{color}"/>')
    head(points[-2], points[-1])
    if double: head(points[1], points[0])

def card(box, title, tag, lines, color='#2563eb'):
    rect(box, '#ffffff')
    x0, y0, x1, y1 = box
    text(x0+24, y0+22, tag, 17, color, True)
    text(x0+24, y0+52, title, 30, '#0f172a', True)
    for i, line in enumerate(lines): text(x0+24, y0+106+i*38, line, 23)

text(50, 40, '视觉识别质检与控制描摹系统', 43, '#0f172a', True)
text(52, 106, '双 FPGA 协同 · 720p 图像采集 · 识别与质检 · 矢量报告与笔迹描摹', 25, '#64748b')
card((50, 210, 300, 390), 'SC500 摄像头', 'INPUT', ['1280 × 720 图像'], '#2563eb')
card((390, 185, 840, 465), '主 FPGA', 'CAPTURE / DISPLAY', ['摄像头采集 · ISP · DDR 缓存', '图像处理 · 运动区域检测', 'HDMI 信息叠加 · 任务调度'])
card((1040, 210, 1550, 390), 'HDMI 显示器', 'DISPLAY', ['实时画面 · 目标框 · PCB 状态'], '#2563eb')
card((390, 580, 840, 915), '副 FPGA', 'INFERENCE / PATH PLANNING', ['DDR 图像缓存 · HXA1 帧接收', '普通 CNN · 固定窗口 PCB 二分类', '笔迹提取 · 骨架与路径规划', '矢量报告 · G-code · 应答控制'], '#00897b')
card((1010, 595, 1250, 750), '无线桥接', 'UART / WIRELESS', ['串口数据转发'], '#a16207')
card((1330, 595, 1550, 750), 'GRBL', 'CONTROLLER', ['运动执行控制'], '#a16207')
rect((1010, 825, 1550, 915), '#ffffff')
text(1034, 850, '写字机', 29, '#0f172a', True)
text(1170, 855, '报告书写 / 中心线描摹', 23)
arrow([(300,300),(390,300)], '#2563eb')
text(315, 258, '图像', 19, '#2563eb')
arrow([(840,300),(1040,300)], '#2563eb')
text(899, 258, 'HDMI', 21, '#2563eb')
arrow([(615,465),(615,580)], '#00897b', True)
text(650, 483, '以太网', 22, '#00897b', True)
text(650, 519, 'HXA1 图像 / Type18 结果', 20, '#00897b')
arrow([(840,675),(1010,675)], '#00897b', True)
text(858, 610, 'UART', 20, '#00897b')
text(856, 640, '115200 8N1', 18, '#00897b')
arrow([(1250,675),(1330,675)], '#a16207', True)
text(1262, 638, '无线', 18, '#a16207')
arrow([(1440,750),(1440,825)], '#a16207')
text(1170, 777, '步进 / 抬笔控制', 21, '#a16207')
text(50, 966, '图像采集与显示', 22, '#2563eb', True)
text(390, 966, '识别、质检与路径生成', 22, '#00897b', True)
text(1010, 966, '通信桥接与机械执行', 22, '#a16207', True)
svg.append('</svg>')
(OUT/'system-architecture.svg').write_text('\n'.join(svg)+'\n', encoding='utf-8')
im.save(OUT/'system-architecture.png', optimize=True)
print('Generated system-architecture.svg and system-architecture.png')
