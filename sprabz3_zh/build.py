#!/usr/bin/env python3
# 由 content.txt 生成中文 Markdown 与 PDF
import os, re, html
from PIL import Image as PILImage

BASE = os.path.dirname(os.path.abspath(__file__))
FIG  = os.path.join(BASE, "fig")
SRC  = os.path.join(BASE, "content.txt")
MD   = os.path.join(BASE, "..", "SPRABZ3_无感梯形波BLDC控制_中文翻译.md")
PDF  = os.path.join(BASE, "..", "SPRABZ3_无感梯形波BLDC控制_中文翻译.pdf")

from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab import rl_config
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_JUSTIFY
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (BaseDocTemplate, PageTemplate, Frame, Paragraph,
                                Spacer, Image, Table, TableStyle, PageBreak,
                                NextPageTemplate, KeepTogether, Preformatted,
                                CondPageBreak)
from reportlab.platypus.tableofcontents import TableOfContents

FONTS = os.path.join(BASE, "fonts")
pdfmetrics.registerFont(TTFont("NotoSC", os.path.join(FONTS, "NotoSansSC-Regular.ttf")))
pdfmetrics.registerFont(TTFont("NotoSC-Bd", os.path.join(FONTS, "NotoSansSC-Bold.ttf")))
pdfmetrics.registerFont(TTFont("NotoMono",
                               "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"))
pdfmetrics.registerFontFamily("NotoSC", normal="NotoSC", bold="NotoSC-Bd",
                              italic="NotoSC", boldItalic="NotoSC-Bd")
rl_config.canvas_basefontname = "NotoSC"
from reportlab.pdfgen.canvas import Canvas as _Canvas
_Canvas._baseFontName = "NotoSC"

NAVY = colors.HexColor("#1B3A63")
INK  = colors.HexColor("#1A1A1A")
GREY = colors.HexColor("#5A5A5A")
LINE = colors.HexColor("#9BB0C6")
BOXBG= colors.HexColor("#F2F6FA")
WARNBG=colors.HexColor("#FDF3E7")

BODY = ParagraphStyle("BODY", fontName="NotoSC", fontSize=10, leading=16.0,
                      textColor=INK, alignment=TA_JUSTIFY, wordWrap="CJK",
                      spaceAfter=6)
BUL  = ParagraphStyle("BUL", parent=BODY, leftIndent=14, bulletIndent=4,
                      spaceAfter=3.5, alignment=TA_LEFT,
                      bulletFontName="NotoSC", bulletFontSize=10)
SUB  = ParagraphStyle("SUB", parent=BUL, leftIndent=30, bulletIndent=20,
                      bulletFontName="NotoSC", bulletFontSize=10)
H1   = ParagraphStyle("H1", fontName="NotoSC-Bd", fontSize=19, leading=26,
                      textColor=NAVY, spaceBefore=2, spaceAfter=10)
H2   = ParagraphStyle("H2", fontName="NotoSC-Bd", fontSize=14.5, leading=21,
                      textColor=NAVY, spaceBefore=14, spaceAfter=7)
H3   = ParagraphStyle("H3", fontName="NotoSC-Bd", fontSize=11.8, leading=17,
                      textColor=NAVY, spaceBefore=11, spaceAfter=5)
H4   = ParagraphStyle("H4", fontName="NotoSC-Bd", fontSize=10.5, leading=15,
                      textColor=colors.HexColor("#2E5A88"), spaceBefore=8, spaceAfter=4)
META = ParagraphStyle("META", fontName="NotoSC", fontSize=9, leading=13.5,
                      textColor=GREY, spaceAfter=2)
SUBT = ParagraphStyle("SUBT", fontName="NotoSC", fontSize=11.5, leading=16,
                      textColor=colors.HexColor("#3D6DA3"), spaceAfter=6)
EQ   = ParagraphStyle("EQ", fontName="NotoSC", fontSize=10.5, leading=16,
                      alignment=TA_CENTER, textColor=INK, spaceBefore=4, spaceAfter=4)
CODE = ParagraphStyle("CODE", fontName="NotoMono", fontSize=8.3, leading=11.6,
                      textColor=colors.HexColor("#12303F"), leftIndent=12,
                      spaceBefore=2, spaceAfter=2)
CAP  = ParagraphStyle("CAP", fontName="NotoSC", fontSize=8.6, leading=12.5,
                      alignment=TA_CENTER, textColor=GREY, spaceBefore=4, spaceAfter=11)
SMALL= ParagraphStyle("SMALL", fontName="NotoSC", fontSize=8.4, leading=12.4,
                      textColor=GREY, spaceAfter=3, wordWrap="CJK")
TBLT = ParagraphStyle("TBLT", fontName="NotoSC-Bd", fontSize=9.6, leading=14,
                      alignment=TA_CENTER, textColor=NAVY, spaceBefore=8, spaceAfter=4)
TC   = ParagraphStyle("TC", fontName="NotoSC", fontSize=8.6, leading=12.4,
                      textColor=INK, wordWrap="CJK")
TCH  = ParagraphStyle("TCH", fontName="NotoSC-Bd", fontSize=8.8, leading=12.6,
                      textColor=NAVY, wordWrap="CJK", alignment=TA_CENTER)
TOCH = ParagraphStyle("TOCH", fontName="NotoSC-Bd", fontSize=15, leading=22,
                      textColor=NAVY, spaceAfter=10)

PW, PH = A4
LM = RM = 50; TM = 52; BM = 46
FW = PW - LM - RM
FH = PH - TM - BM
LW, LH = landscape(A4)
LM_H = RM_H = 22; TM_H = 20; BM_H = 22
FW_L = LW - LM_H - RM_H
FH_L = LH - TM_H - BM_H

def esc(t):
    t = t.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    return re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", t)

def footer(canv, doc):
    canv.saveState()
    canv.setFont("NotoSC", 8)
    canv.setFillColor(GREY)
    canv.drawCentredString(PW / 2.0, 24, "第 %d 页" % canv.getPageNumber())
    canv.restoreState()

def footer_land(canv, doc):
    canv.saveState()
    canv.setFont("NotoSC", 8)
    canv.setFillColor(GREY)
    canv.drawCentredString(LW / 2.0, 12, "第 %d 页" % canv.getPageNumber())
    canv.restoreState()

class Doc(BaseDocTemplate):
    def afterFlowable(self, flowable):
        if isinstance(flowable, Paragraph):
            s = flowable.style.name
            if s in ("H2", "H3"):
                self.notify("TOCEntry", (0 if s == "H2" else 1,
                                         flowable.getPlainText(), self.page))

def box(text, bg, bar):
    p = Paragraph(esc(text), ParagraphStyle("bx", parent=SMALL, textColor=INK,
                                           fontSize=9, leading=13.5))
    t = Table([[p]], colWidths=[FW])
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), bg),
        ("LINEBEFORE", (0, 0), (0, -1), 2.2, bar),
        ("LEFTPADDING", (0, 0), (-1, -1), 8),
        ("RIGHTPADDING", (0, 0), (-1, -1), 8),
        ("TOPPADDING", (0, 0), (-1, -1), 6),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
    ]))
    return t

def fit(path, max_w, max_h):
    iw, ih = PILImage.open(path).size
    r = min(max_w / float(iw), max_h / float(ih))
    return iw * r, ih * r

# 图形在原 PDF 中的实际尺寸（pt），用于避免把小图放大到模糊
import json as _json
_man = _json.load(open(os.path.join(FIG, "manifest.json"), encoding="utf-8"))
NAT = {}
for _k, _v in _man.items():
    if _v.get("rect"):
        r = _v["rect"]
        NAT[_k] = (abs(r[2] - r[0]), abs(r[3] - r[1]))
    else:                      # 整页框图（原为横向整页）
        NAT[_k] = (792.0, 612.0)

def fit_nat(fid, path, max_w, max_h, mag=2.2):
    """按边框缩放，但放大倍数不超过 mag，保证清晰度"""
    iw, ih = PILImage.open(path).size
    nw, nh = NAT.get(fid, (iw, ih))
    r = min(max_w / float(iw), max_h / float(ih), mag * nw / float(iw),
            mag * nh / float(ih))
    return iw * r, ih * r

# ---------------- parse ----------------
raw = open(SRC, encoding="utf-8").read().split("\n")
items = []           # (kind, payload)
i = 0
while i < len(raw):
    ln = raw[i]
    s = ln.rstrip()
    if not s.strip():
        i += 1; continue
    if s.startswith("#### "):  items.append(("h4", s[5:].strip()))
    elif s.startswith("### "): items.append(("h3", s[4:].strip()))
    elif s.startswith("## "):  items.append(("h2", s[3:].strip()))
    elif s.startswith("# "):   items.append(("h1", s[2:].strip()))
    elif s.startswith("@meta "): items.append(("meta", s[6:].strip()))
    elif s.startswith("@subtitle "): items.append(("subtitle", s[10:].strip()))
    elif s.startswith("@eq "):   items.append(("eq", s[4:].strip()))
    elif s.startswith("@caption "): items.append(("cap", s[9:].strip()))
    elif s.startswith("@note "): items.append(("note", s[6:].strip()))
    elif s.startswith("@warn "): items.append(("warn", s[6:].strip()))
    elif s.startswith("@small "): items.append(("small", s[7:].strip()))
    elif s.startswith("@tbltitle "): items.append(("tbltitle", s[10:].strip()))
    elif s.startswith("@diagpage "):
        a = s[10:].split("|")
        items.append(("diag", (a[0].strip(), a[1].strip() if len(a) > 1 else "")))
    elif s.startswith("@figrow "):
        items.append(("figrow", [x.strip() for x in s[8:].split("|")]))
    elif s.startswith("@fig "):
        a = s[5:].split("|")
        items.append(("fig", (a[0].strip(), a[1].strip() if len(a) > 1 else "")))
    elif s.startswith("@pb"):
        items.append(("pb", None))
    elif s.startswith("@tbl "):
        parts = s.split()
        n = int(parts[1]); ws = [float(x) for x in parts[2:2 + n]]
        fsz = next((float(x[3:]) for x in parts[2 + n:] if x.startswith("fs=")), None)
        rows = []
        i += 1
        while i < len(raw) and not raw[i].startswith("@endtbl"):
            r = raw[i].strip()
            if r.startswith("|"):
                cells = [c.strip() for c in r.strip("|").split("|")]
                rows.append(cells)
            i += 1
        items.append(("tbl", (n, ws, rows, fsz)))
    elif s.startswith("@code "):
        block = []
        while i < len(raw) and raw[i].startswith("@code "):
            block.append(raw[i][6:])
            i += 1
        items.append(("code", "\n".join(block)))
        continue
    elif s.startswith("- "):
        items.append(("bul", s[2:].strip()))
    elif s.startswith("  - "):
        items.append(("sub", s[4:].strip()))
    else:
        items.append(("p", s.strip()))
    i += 1

# 把 "表标题 + 表格 + 表下脚注" 归为一块，避免标题与表格分页
grouped = []
_i = 0
while _i < len(items):
    _k, _v = items[_i]
    if _k == "tbltitle":
        _title = _v; _i += 1; _tbl = None; _smalls = []
        if _i < len(items) and items[_i][0] == "tbl":
            _tbl = items[_i][1]; _i += 1
        while _i < len(items) and items[_i][0] == "small":
            _smalls.append(items[_i][1]); _i += 1
        grouped.append(("tblblock", (_title, _tbl, _smalls)))
        continue
    grouped.append((_k, _v)); _i += 1
items = grouped

# ---------------- markdown ----------------
md = []
for k, v in items:
    if k == "h1":   md.append("# " + v)
    elif k == "h2": md.append("\n## " + v)
    elif k == "h3": md.append("\n### " + v)
    elif k == "h4": md.append("\n#### " + v)
    elif k == "p":  md.append("\n" + v)
    elif k == "bul":md.append("- " + v)
    elif k == "sub":md.append("  - " + v)
    elif k == "meta": md.append("> " + v)
    elif k == "subtitle": md.append("\n*" + v + "*")
    elif k == "eq": md.append("\n$$ " + v + " $$")
    elif k == "note": md.append("\n> " + v)
    elif k == "warn": md.append("\n> **" + v + "**")
    elif k == "small": md.append("\n*" + v + "*")
    elif k == "code": md.append("\n```\n" + v + "\n```")
    elif k == "caption": md.append("*" + v + "*")
    elif k == "tblblock":
        title, tb, smalls = v
        md.append("\n**" + title + "**\n")
        if tb:
            n, ws, rows = tb[0], tb[1], tb[2]
            for ri, r in enumerate(rows):
                md.append("| " + " | ".join(r) + " |")
                if ri == 0:
                    md.append("|" + "|".join([" --- "] * n) + "|")
        for sm in smalls:
            md.append("\n*" + sm + "*")
    elif k == "tbltitle": md.append("\n**" + v + "**\n")
    elif k == "tbl":
        n, ws, rows = v
        for ri, r in enumerate(rows):
            md.append("| " + " | ".join(r) + " |")
            if ri == 0:
                md.append("|" + "|".join([" --- "] * n) + "|")
    elif k == "fig":
        md.append("\n![%s](sprabz3_zh/fig/%s.png)\n" % (v[1], v[0]))
    elif k == "figrow":
        a = v
        for j in range(0, len(a) - 1, 2):
            md.append("\n![%s](sprabz3_zh/fig/%s.png)\n" % (a[j + 1], a[j]))
    elif k == "diag":
        md.append("\n### %s\n\n![%s](sprabz3_zh/fig/%s.png)\n" % (v[1], v[1], v[0]))
    elif k == "pb":
        md.append("\n---\n")
open(MD, "w", encoding="utf-8").write("\n".join(md) + "\n")
print("markdown ->", os.path.normpath(MD))

# ---------------- pdf ----------------
story = []
toc = TableOfContents()
toc.levelStyles = [
    ParagraphStyle("t1", fontName="NotoSC", fontSize=10, leading=17,
                   leftIndent=0, textColor=INK),
    ParagraphStyle("t2", fontName="NotoSC", fontSize=9, leading=15,
                   leftIndent=16, textColor=GREY),
]
first_h1 = True
for k, v in items:
    if k == "h1":
        story.append(Paragraph(esc(v), H1))
        story.append(Spacer(1, 4))
    elif k == "meta":
        story.append(Paragraph(esc(v), META))
    elif k == "subtitle":
        story.append(Paragraph(esc(v), SUBT))
    elif k == "h2":
        story.append(CondPageBreak(FH * 0.18))
        story.append(Paragraph(esc(v), H2))
    elif k == "h3":
        if v == "目录":
            pass
        story.append(CondPageBreak(FH * 0.14))
        story.append(Paragraph(esc(v), H3))
    elif k == "h4":
        story.append(Paragraph(esc(v), H4))
    elif k == "p":
        story.append(Paragraph(esc(v), BODY))
    elif k == "bul":
        story.append(Paragraph(esc(v), BUL, bulletText="\u2022"))
    elif k == "sub":
        story.append(Paragraph(esc(v), SUB, bulletText="\u2013"))
    elif k == "eq":
        story.append(Paragraph(esc(v), EQ))
    elif k == "code":
        story.append(Preformatted(v, CODE))
        story.append(Spacer(1, 4))
    elif k == "caption":
        story.append(Paragraph(esc(v), CAP))
    elif k == "note":
        story.append(Spacer(1, 3)); story.append(box(v, BOXBG, LINE)); story.append(Spacer(1, 7))
    elif k == "warn":
        story.append(Spacer(1, 3)); story.append(box(v, WARNBG, colors.HexColor("#D08A2C")))
        story.append(Spacer(1, 7))
    elif k == "small":
        story.append(Paragraph(esc(v), SMALL))
    elif k == "tblblock":
        title, tb, smalls = v
        blk = [Paragraph(esc(title), TBLT)]
        if tb:
            n, ws, rows = tb[0], tb[1], tb[2]
            cw = [FW * x / sum(ws) for x in ws]
            data = []
            for ri, r in enumerate(rows):
                st = TCH if ri == 0 else TC
                data.append([Paragraph(esc(c), st) for c in r])
            t = Table(data, colWidths=cw, repeatRows=1, hAlign="CENTER")
            t.setStyle(TableStyle([
                ("GRID", (0, 0), (-1, -1), 0.5, LINE),
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#E4EDF6")),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("LEFTPADDING", (0, 0), (-1, -1), 5),
                ("RIGHTPADDING", (0, 0), (-1, -1), 5),
                ("TOPPADDING", (0, 0), (-1, -1), 3.5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 3.5),
            ]))
            blk.append(t)
        for sm in smalls:
            blk.append(Paragraph(esc(sm), SMALL))
        story.append(KeepTogether(blk))
        story.append(Spacer(1, 9))
    elif k == "tbltitle":
        story.append(Paragraph(esc(v), TBLT))
    elif k == "tbl":
        n, ws, rows = v
        cw = [FW * x / sum(ws) for x in ws]
        data = []
        for ri, r in enumerate(rows):
            st = TCH if ri == 0 else TC
            data.append([Paragraph(esc(c), st) for c in r])
        t = Table(data, colWidths=cw, repeatRows=1, hAlign="CENTER")
        t.setStyle(TableStyle([
            ("GRID", (0, 0), (-1, -1), 0.5, LINE),
            ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#E4EDF6")),
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ("LEFTPADDING", (0, 0), (-1, -1), 5),
            ("RIGHTPADDING", (0, 0), (-1, -1), 5),
            ("TOPPADDING", (0, 0), (-1, -1), 3.5),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 3.5),
        ]))
        story.append(t)
        story.append(Spacer(1, 8))
    elif k == "fig":
        fid, cap = v
        p = os.path.join(FIG, fid + ".png")
        w, h = fit_nat(fid, p, FW, FH * 0.92)
        im = Image(p, width=w, height=h, hAlign="CENTER")
        grp = [im, Paragraph(esc(cap), CAP)] if cap else [im, Spacer(1, 10)]
        story.append(KeepTogether(grp))
    elif k == "figrow":
        a = v
        imgs, caps, natw = [], [], []
        for j in range(0, len(a) - 1, 2):
            p = os.path.join(FIG, a[j] + ".png")
            iw, ih = PILImage.open(p).size
            nw, nh = NAT.get(a[j], (iw, ih))
            imgs.append((p, iw, ih, nw, nh)); caps.append(a[j + 1]); natw.append(nw)
        gap = 16.0
        s = min(1.5, (FW - gap * (len(imgs) - 1)) / sum(natw),
                (FH * 0.5) / max(nh for *_, nh in imgs))
        row1, row2, cols = [], [], []
        for idx, (p, iw, ih, nw, nh) in enumerate(imgs):
            w, h = nw * s, nh * s
            if idx:
                row1.append(Spacer(1, gap)); row2.append(Spacer(1, gap)); cols.append(gap)
            row1.append(Image(p, width=w, height=h, hAlign="CENTER"))
            row2.append(Paragraph(esc(caps[idx]), CAP)); cols.append(w)
        tb = Table([row1, row2], colWidths=cols, hAlign="CENTER")
        tb.setStyle(TableStyle([("VALIGN", (0, 0), (-1, 0), "BOTTOM"),
                                ("VALIGN", (0, 1), (-1, 1), "TOP"),
                                ("TOPPADDING", (0, 0), (-1, -1), 0),
                                ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
                                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                                ("RIGHTPADDING", (0, 0), (-1, -1), 0)]))
        story.append(KeepTogether([tb, Spacer(1, 8)]))
    elif k == "diag":
        fid, head = v
        p = os.path.join(FIG, fid + ".png")
        w, h = fit_nat(fid, p, FW_L, FH_L, mag=3.0)
        while story and isinstance(story[-1], PageBreak):
            story.pop()
        story.append(NextPageTemplate("landscape"))
        story.append(PageBreak())
        story.append(Image(p, width=w, height=h, hAlign="CENTER"))
        story.append(NextPageTemplate("portrait"))
        story.append(PageBreak())
    elif k == "pb":
        story.append(PageBreak())

# 目录插到标题/元信息之后
ins = 0
for idx, (k, v) in enumerate(items):
    if k in ("meta",):
        ins = idx + 1
if ins:
    story.insert(ins + 1, Spacer(1, 6))
    story.insert(ins + 2, Paragraph("目录", TOCH))
    story.insert(ins + 3, toc)
    story.insert(ins + 4, PageBreak())

fp = Frame(LM, BM, FW, FH, id="fp", leftPadding=0, rightPadding=0,
           topPadding=0, bottomPadding=0)
fl = Frame(LM_H, BM_H, FW_L, FH_L, id="fl", leftPadding=0, rightPadding=0,
           topPadding=0, bottomPadding=0)
doc = Doc(PDF, pagesize=A4, leftMargin=LM, rightMargin=RM,
          topMargin=TM, bottomMargin=BM,
          title="无刷直流电机的无位置传感器梯形波控制（DRV8312-EVM）",
          author="Texas Instruments（SPRABZ3）／中文翻译",
          subject="TI 应用报告 SPRABZ3 中文译文",
          creator="ReportLab")
doc.addPageTemplates([
    PageTemplate(id="portrait", frames=[fp], pagesize=A4, onPage=footer),
    PageTemplate(id="landscape", frames=[fl], pagesize=landscape(A4), onPage=footer_land),
])
doc.multiBuild(story)
print("pdf ->", os.path.normpath(PDF))
