"""生成 SysPulse 应用图标（1024x1024 PNG）。

设计：macOS 圆角深色底 + 一条上升的折线（系统监控语义）+ 青色端点高亮。
运行：python3 make_icon.py
"""

from PIL import Image, ImageDraw, ImageFilter

S = 1024
OUT = "Resources/icon_1024.png"

img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

margin = 92
rect = [margin, margin, S - margin, S - margin]
radius = int((S - 2 * margin) * 0.2237)  # macOS squircle 近似

# ---- 背景竖向渐变 ----
grad = Image.new("RGBA", (S, S))
gd = ImageDraw.Draw(grad)
top = (45, 52, 86)      # #2D3456
bottom = (15, 17, 32)   # #0F1120
for y in range(S):
    t = y / (S - 1)
    gd.line([(0, y), (S, y)], fill=(
        round(top[0] * (1 - t) + bottom[0] * t),
        round(top[1] * (1 - t) + bottom[1] * t),
        round(top[2] * (1 - t) + bottom[2] * t),
        255,
    ))

mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle(rect, radius=radius, fill=255)
img.paste(grad, (0, 0), mask)

# ---- 折线路径 ----
x0, y0 = margin + 120, margin + 175
x1, y1 = S - margin - 120, S - margin - 135


def pt(fx, fy):
    return (x0 + fx * (x1 - x0), y1 - fy * (y1 - y0))


pts = [
    pt(0.00, 0.20),
    pt(0.17, 0.50),
    pt(0.34, 0.34),
    pt(0.51, 0.70),
    pt(0.68, 0.52),
    pt(0.84, 0.80),
    pt(1.00, 1.00),
]

line_color = (52, 211, 153, 255)  # emerald

# ---- 柔光 ----
glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(glow).line(pts, fill=(52, 211, 153, 130), width=64, joint="curve")
glow = glow.filter(ImageFilter.GaussianBlur(30))
img.alpha_composite(glow)

# ---- 主线 ----
draw = ImageDraw.Draw(img)
draw.line(pts, fill=line_color, width=40, joint="curve")
for p in pts:
    r = 20
    draw.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=line_color)

# ---- 端点高亮 ----
ex, ey = pts[-1]
er = 48
draw.ellipse([ex - er, ey - er, ex + er, ey + er], fill=(34, 211, 238, 255))
ir = 20
draw.ellipse([ex - ir, ey - ir, ex + ir, ey + ir], fill=(255, 255, 255, 255))

img.save(OUT)
print(f"saved {OUT}")
