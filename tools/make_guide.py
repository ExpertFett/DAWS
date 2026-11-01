"""Build the DAWG User Guide PDF (ships in the release zip).

    python tools/make_guide.py      -> docs/DAWG_User_Guide.pdf
"""
import os
import re

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import inch
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (KeepTogether, PageBreak, Paragraph, Preformatted, SimpleDocTemplate, Spacer, Table,
                                TableStyle)
from reportlab.graphics.shapes import Drawing, Line, Polygon, Rect, String

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "DAWG_User_Guide.pdf")
# the bundled missions, straight from the packager (so the guide never names a stale build)
BUNDLE = re.search(r"BUNDLE_MISSIONS = \[([^\]]+)\]", open(os.path.join(ROOT, "tools", "package.py"), encoding="utf-8").read()).group(1)
STARTER = re.search(r'"([^"]*Starter[^"]*)"', BUNDLE).group(1)
DEMO = re.search(r'"([^"]*Demo[^"]*)"', BUNDLE).group(1)
VERSION = re.search(r'local VERSION = "([^"]+)"', open(os.path.join(ROOT, "DAWG.lua"), encoding="utf-8").read()).group(1)

FONTS = r"C:\Windows\Fonts"
pdfmetrics.registerFont(TTFont("Body", os.path.join(FONTS, "calibri.ttf")))
pdfmetrics.registerFont(TTFont("Body-B", os.path.join(FONTS, "calibrib.ttf")))
pdfmetrics.registerFont(TTFont("Body-I", os.path.join(FONTS, "calibrii.ttf")))
pdfmetrics.registerFont(TTFont("Mono", os.path.join(FONTS, "consola.ttf")))
pdfmetrics.registerFont(TTFont("Mono-B", os.path.join(FONTS, "consolab.ttf")))
from reportlab.pdfbase.pdfmetrics import registerFontFamily  # noqa: E402
registerFontFamily("Body", normal="Body", bold="Body-B", italic="Body-I", boldItalic="Body-B")
registerFontFamily("Mono", normal="Mono", bold="Mono-B", italic="Mono", boldItalic="Mono-B")

NAVY = colors.HexColor("#1f2f4a")
ACCENT = colors.HexColor("#c0392b")
SOFT = colors.HexColor("#eef2f7")
LINE = colors.HexColor("#c9d3e0")
CODEBG = colors.HexColor("#f4f4f2")
MUTED = colors.HexColor("#5a6475")

ST = {
    "title": ParagraphStyle("title", fontName="Body-B", fontSize=34, leading=38, textColor=NAVY, alignment=TA_CENTER),
    "subtitle": ParagraphStyle("subtitle", fontName="Body", fontSize=15, leading=20, textColor=MUTED, alignment=TA_CENTER),
    "h1": ParagraphStyle("h1", fontName="Body-B", fontSize=19, leading=23, textColor=NAVY, spaceBefore=4, spaceAfter=8),
    "h2": ParagraphStyle("h2", fontName="Body-B", fontSize=13.5, leading=17, textColor=NAVY, spaceBefore=10, spaceAfter=4),
    "body": ParagraphStyle("body", fontName="Body", fontSize=10.5, leading=14.5, spaceAfter=6),
    "small": ParagraphStyle("small", fontName="Body", fontSize=9, leading=12, textColor=MUTED),
    "cell": ParagraphStyle("cell", fontName="Body", fontSize=9.5, leading=12.5),
    "cellb": ParagraphStyle("cellb", fontName="Body-B", fontSize=9.5, leading=12.5),
    "head": ParagraphStyle("head", fontName="Body-B", fontSize=9.5, leading=12.5, textColor=colors.white),
    "bullet": ParagraphStyle("bullet", fontName="Body", fontSize=10.5, leading=14.5, leftIndent=14, bulletIndent=3, spaceAfter=3),
    "code": ParagraphStyle("code", fontName="Mono", fontSize=8.6, leading=11.2, textColor=colors.HexColor("#222222")),
    "note": ParagraphStyle("note", fontName="Body", fontSize=10, leading=13.5, textColor=colors.HexColor("#3a3a3a")),
}


def P(t, s="body"):
    return Paragraph(t, ST[s])


def C(t):
    """Inline code."""
    return '<font name="Mono" size="9" color="#8a1c12">%s</font>' % t


def bullets(items):
    return [Paragraph(i, ST["bullet"], bulletText="\u2022") for i in items]


def table(rows, widths, head=True, zebra=True):
    data = []
    for r, row in enumerate(rows):
        cells = []
        for c, v in enumerate(row):
            if isinstance(v, str):
                style = "head" if (head and r == 0) else ("cellb" if c == 0 else "cell")
                v = Paragraph(v, ST[style])
            cells.append(v)
        data.append(cells)
    t = Table(data, colWidths=widths, repeatRows=1 if head else 0)
    cmds = [("VALIGN", (0, 0), (-1, -1), "TOP"),
            ("LINEBELOW", (0, 0), (-1, -1), 0.4, LINE),
            ("TOPPADDING", (0, 0), (-1, -1), 4), ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
            ("LEFTPADDING", (0, 0), (-1, -1), 6), ("RIGHTPADDING", (0, 0), (-1, -1), 6)]
    if head:
        cmds += [("BACKGROUND", (0, 0), (-1, 0), NAVY)]
    if zebra:
        for r in range(1 if head else 0, len(rows)):
            if (r % 2 == 0) == head:
                cmds.append(("BACKGROUND", (0, r), (-1, r), SOFT))
    t.setStyle(TableStyle(cmds))
    return t


def code(text):
    pre = Preformatted(text.strip("\n"), ST["code"])
    t = Table([[pre]], colWidths=[6.9 * inch])
    t.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, -1), CODEBG), ("BOX", (0, 0), (-1, -1), 0.5, LINE),
                           ("LEFTPADDING", (0, 0), (-1, -1), 8), ("RIGHTPADDING", (0, 0), (-1, -1), 8),
                           ("TOPPADDING", (0, 0), (-1, -1), 6), ("BOTTOMPADDING", (0, 0), (-1, -1), 6)]))
    return t


def callout(text, color=ACCENT):
    t = Table([[Paragraph(text, ST["note"])]], colWidths=[6.9 * inch])
    t.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#fbf3f2") if color == ACCENT else SOFT),
                           ("LINEBEFORE", (0, 0), (0, -1), 3, color),
                           ("LEFTPADDING", (0, 0), (-1, -1), 10), ("RIGHTPADDING", (0, 0), (-1, -1), 8),
                           ("TOPPADDING", (0, 0), (-1, -1), 6), ("BOTTOMPADDING", (0, 0), (-1, -1), 6)]))
    return t


def flow():
    """The life of a probe."""
    W, H = 6.9 * inch, 2.55 * inch
    d = Drawing(W, H)

    def box(x, y, w, h, label, sub=None, fill=SOFT, stroke=NAVY, fg=NAVY, subfg=MUTED):
        d.add(Rect(x, y, w, h, rx=5, ry=5, fillColor=fill, strokeColor=stroke, strokeWidth=1))
        d.add(String(x + w / 2, y + h / 2 + (3 if sub else -3.5), label, fontName="Body-B", fontSize=9.5,
                     fillColor=fg, textAnchor="middle"))
        if sub:
            d.add(String(x + w / 2, y + h / 2 - 9, sub, fontName="Body", fontSize=7.5, fillColor=subfg, textAnchor="middle"))

    def arrow(x1, y1, x2, y2):
        d.add(Line(x1, y1, x2, y2, strokeColor=NAVY, strokeWidth=1))
        import math
        a = math.atan2(y2 - y1, x2 - x1)
        p = [x2, y2, x2 - 6 * math.cos(a - 0.4), y2 - 6 * math.sin(a - 0.4), x2 - 6 * math.cos(a + 0.4), y2 - 6 * math.sin(a + 0.4)]
        d.add(Polygon(p, fillColor=NAVY, strokeColor=NAVY))

    y = H / 2 - 16
    box(0, y, 64, 32, "LAUNCH", "from his field")
    arrow(64, y + 16, 78, y + 16)
    box(78, y, 74, 32, "PROBE", "along the border")
    arrow(152, y + 16, 166, y + 16)
    box(166, y, 76, 32, "IDENTIFIED", "you got close")
    # no answer loop
    d.add(String(115, y - 22, "nobody comes \u2192 next lap closer", fontName="Body-I", fontSize=7.5, fillColor=ACCENT, textAnchor="middle"))
    # reactions
    rows = [("By-the-book", "complies \u2192 goes home"),
            ("Showboat", "1-2 close passes \u2192 home"),
            ("Hothead", "fuel dump + passes \u2192 walk him out"),
            ("Tester", "complies \u2192 turns BACK if left")]
    bx, bw, bh = 262, 172, 30
    ys = [H - 36, H - 36 - 40, H - 36 - 80, H - 36 - 120]
    for (name, what), yy in zip(rows, ys):
        arrow(242, y + 16, bx, yy + bh / 2)
        box(bx, yy, bw, bh, name, what, fill=colors.white)
    box(bx + bw + 12, H / 2 - 16, W - (bx + bw + 12) - 1, 32, "ESCORTED", "OUT", fill=NAVY, fg=colors.white, subfg=colors.white)
    for yy in ys:
        d.add(Line(bx + bw, yy + bh / 2, bx + bw + 12, H / 2, strokeColor=LINE, strokeWidth=0.8))
    return d


def on_page(canvas, doc):
    canvas.saveState()
    if doc.page > 1:
        canvas.setFillColor(NAVY)
        canvas.rect(0, letter[1] - 0.42 * inch, letter[0], 0.42 * inch, fill=1, stroke=0)
        canvas.setFillColor(colors.white)
        canvas.setFont("Body-B", 10)
        canvas.drawString(0.8 * inch, letter[1] - 0.27 * inch, "DAWG  \u00b7  Dynamic Air Warfare Group")
        canvas.setFont("Body", 9)
        canvas.drawRightString(letter[0] - 0.8 * inch, letter[1] - 0.27 * inch, "User Guide  v" + VERSION)
    canvas.setFillColor(MUTED)
    canvas.setFont("Body", 8.5)
    canvas.drawString(0.8 * inch, 0.45 * inch, "github.com/ExpertFett/DAWG")
    canvas.drawRightString(letter[0] - 0.8 * inch, 0.45 * inch, "Page %d" % doc.page)
    canvas.restoreState()


def build():
    s = []
    W = 6.9 * inch

    # ------------------------------------------------------------------ cover
    s += [Spacer(1, 0.85 * inch), P("DAWG", "title"), Spacer(1, 4), P("Dynamic Air Warfare Group", "subtitle"),
          Spacer(1, 6), P("User Guide \u00b7 v%s" % VERSION, "subtitle"), Spacer(1, 0.35 * inch)]
    s.append(callout("DAWG is a mission script for DCS World. Fighters launch from their own fields and <b>probe your border</b>: "
                     "they fly along it, never cross it, and time how long you take to respond. When you intercept them, each one "
                     "reacts according to the <b>pilot</b> it drew. One complies and goes home. Another dumps fuel across your "
                     "windscreen and won't leave until you walk him out.", NAVY))
    s += [Spacer(1, 0.22 * inch), flow(), Spacer(1, 0.22 * inch)]
    s.append(table([
        ["What you get", ""],
        ["No Lua needed", "Set everything up in the Mission Editor with group names and flags."],
        ["Four pilot types", "By-the-book, showboat, hothead, tester. Pick them, or let DAWG pick at random."],
        ["Real borders", "The real Caucasus borders are built in. On other maps, draw your own zones."],
        ["Safe by design", "Never crosses a border, never shoots. Close passes keep at least 100 m and abort inside 50 m."],
        ["They talk back", "With DCS-ATC in the mission, hail them on Guard and give orders; each pilot answers in character."],
        ["Multiplayer", "Runs on the server. Players need nothing installed."],
    ], [1.6 * inch, W - 1.6 * inch]))
    s.append(Spacer(1, 0.2 * inch))
    s.append(P("Contents: 1 The pilots \u00b7 2 Setup in five steps \u00b7 3 Choosing how pilots act \u00b7 4 Flags \u00b7 "
               "5 Flying against it \u00b7 6 Talking to them on Guard \u00b7 7 Recipes \u00b7 8 The config file \u00b7 9 Troubleshooting", "small"))
    s.append(PageBreak())

    # ------------------------------------------------------------- 1 pilots
    s.append(P("1  The pilots", "h1"))
    s.append(P("Every probe is flown by one of four pilot types. The type decides how close he pushes, what he does once "
               "you've identified him, and how hard he is to get rid of."))
    s.append(table([
        ["Pilot", "Pushes", "Once identified", "Getting rid of him"],
        ["By-the-book", "as drawn", "Complies within a minute and turns for home.", "Easy: just escort him out."],
        ["Showboat", "1 step closer", "Comes over and does 1\u20132 close passes on you.", "Goes home after his passes."],
        ["Hothead", "2 steps closer",
         "Opens with a <b>fuel dump</b> across your nose, then 2\u20134 passes: nose crossings, belly check, over the canopy, sits in your six.",
         "Goes back to his probe track. Sit on his wing ~2.5 minutes and he gives up. Leave him alone and he may turn back."],
        ["Tester", "1 step closer", "Complies quickly, no passes.", "<b>Always</b> turns back if nobody follows him out."],
    ], [1.05 * inch, 0.95 * inch, 2.55 * inch, 2.35 * inch]))
    s.append(Spacer(1, 8))
    s.append(P("Three more behaviours apply to every pilot:", "body"))
    s += bullets([
        "<b>Unanswered probes push closer.</b> If nobody comes out, he runs the leg again a step (4 NM) closer, up to three laps. "
        "He never gets closer than 2 NM to the border.",
        "<b>Lanes remember.</b> A lane nobody defended starts its next probe deeper. A quick intercept and escort pushes it back out.",
        "<b>Shoot at him and he runs.</b> He breaks off and heads home at full speed. Nobody on the probing side ever fires.",
    ])
    s.append(P("Close passes", "h2"))
    s.append(table([
        ["Pass", "What you see"],
        ["Fuel dump", "Crosses ~260 m ahead, slightly high, trailing white smoke you fly through. Needs a smoke pod."],
        ["Nose cross", "Slides across your nose ~400 m ahead."],
        ["Wing look / close wing", "Sits on your wing at ~200 m, or tucks in to ~100 m."],
        ["Belly check", "Slides underneath you at ~130 m."],
        ["Canopy pass", "Passes ~150 m over your canopy."],
        ["Sit six", "Sits in your six at ~450 m, gun range. He doesn't shoot."],
    ], [1.7 * inch, W - 1.7 * inch]))
    s.append(Spacer(1, 6))
    s.append(callout("<b>Safety is automatic.</b> No pass, and no path between two passes, comes inside 100 m. If anything gets "
                     "inside 50 m he aborts and breaks away. Passes pause while you turn hard or fly below 1,500 m above the ground. "
                     "There are no passes near a border or over land."))
    s.append(PageBreak())

    # --------------------------------------------------------------- 2 setup
    s.append(P("2  Setup in five steps", "h1"))
    s.append(P("Everything below is done in the Mission Editor. The fastest way to learn it is to open "
               "<b>missions/" + STARTER + "</b> from the zip, where every step is already done."))

    s.append(P("Step 1 \u2014 Load the script", "h2"))
    s.append(table([
        ["Trigger", "Condition", "Action"],
        ["ONCE", "TIME MORE 1", "DO SCRIPT FILE \u2192 " + C("DAWG_borders_caucasus.lua") + "  (Caucasus only)"],
        ["ONCE", "TIME MORE 2", "DO SCRIPT FILE \u2192 " + C("DAWG.lua") + "  (always last)"],
    ], [1.0 * inch, 1.3 * inch, W - 2.3 * inch]))
    s.append(P("Use DO SCRIPT FILE, not DO SCRIPT with the text pasted in. You don't need to edit MissionScripting.lua.", "small"))

    s.append(P("Step 2 \u2014 Place templates (who flies the probes)", "h2"))
    s.append(P("A template is an aircraft group DAWG copies every time it launches a probe. The original never flies."))
    s += bullets([
        "<b>Side:</b> the probing side (red by default).",
        "<b>Late activation:</b> ON.",
        "<b>Start:</b> Takeoff from runway, at his home field. He takes off, probes and lands back there.",
        "<b>Name:</b> must start with " + C("DAWG") + ", e.g. " + C("DAWG Su-27 Sochi") + ".",
        "<b>ROE:</b> nothing to set. DAWG puts every probe on weapon hold itself.",
        "<b>For the fuel dump:</b> put <b>Smoke Generator \u2013 white</b> on a pylon. The Su-27, Su-33, MiG-29, J-11A, "
        "Su-25 and L-39 can carry one; the MiG-31 can't, so it never dumps fuel.",
        "<b>Size:</b> one aircraft is enough. DAWG sends singles or pairs at random (see the #single / #pair tags).",
    ])

    s.append(P("Step 3 \u2014 Draw lanes (where they probe)", "h2"))
    s.append(P("A lane is the route a probe flies along the border. Draw it with any late-activated group: it never spawns, "
               "it only marks the route."))
    s += bullets([
        "<b>Name:</b> " + C("DAWG LANE GAGRA") + " (any name after DAWG LANE). The name is also used in its flag: " + C("DAWG_LAUNCH_GAGRA") + ".",
        "<b>Waypoints:</b> two or more, drawn <b>parallel to the border and outside it</b>, about 10\u201315 NM off. "
        "DAWG pushes the route closer on its own when nobody answers.",
        "<b>Over land?</b> Add " + C("#land") + " to the name (e.g. " + C("DAWG LANE ROKI #land") + "). There are no passes over land; "
        "you shadow him from your own side, so identifying him only needs 15 NM.",
    ])

    s.append(P("Step 4 \u2014 Borders (what they won't cross)", "h2"))
    s += bullets([
        "<b>Caucasus:</b> nothing to do. Loading " + C("DAWG_borders_caucasus.lua") + " gives the real borders: Georgia (including "
        "Abkhazia and South Ossetia) and its 12 NM sea, Turkey and its 12 NM sea, Armenia and Azerbaijan.",
        "<b>Any other map:</b> draw polygon trigger zones named " + C("DAWG BORDER") + " (anything after it). Every one is off-limits. "
        "Draw a separate polygon for the territorial sea.",
    ])

    s.append(P("Step 5 \u2014 Fly", "h2"))
    s.append(P("That's it. With no other settings, the first probe launches at about 10 minutes, then one every 15\u201325 minutes, "
               "two at most at a time. OVERLORD calls each new track to the defending side."))
    s.append(PageBreak())

    # ------------------------------------------------------- 3 choosing pilots
    s.append(P("3  Choosing how pilots act", "h1"))
    s.append(P("There are four ways to decide who flies a probe, from broadest to most precise. You can mix them: a flag "
               "value beats any tag, a template's tag beats its lane's tag, and any tag beats the random choice."))
    s.append(table([
        ["You want", "Do this", "Example"],
        ["One template always acts a certain way", "Tag the template's name", C("DAWG Su-27 Sochi #hothead")],
        ["A template only flies certain lanes", "Tag it with @ and the lane name", C("DAWG MiG-29 Krymsk @POTI")],
        ["Everyone on a lane acts one way", "Tag the lane's name", C("DAWG LANE GAGRA #showboat")],
        ["This one launch, right now", "Set a launch flag (section 4)", C("DAWG_LAUNCH_GAGRA") + " = 4"],
        ["Random", "Do nothing", "45% book \u00b7 30% showboat \u00b7 15% hothead \u00b7 10% tester"],
    ], [2.15 * inch, 2.0 * inch, W - 4.15 * inch]))
    s.append(P("All the name tags", "h2"))
    s.append(table([
        ["Tag", "On", "Effect"],
        [C("#book") + "  " + C("#showboat") + "  " + C("#hothead") + "  " + C("#tester"), "template or lane", "Always this pilot type."],
        [C("@GAGRA") + "  " + C("@POTI") + "  \u2026", "template", "Flies only these lanes (you can list several). Without any @, he flies every lane."],
        [C("#nostunts"), "template", "Never does close passes (e.g. a bomber, or a well-behaved escort)."],
        [C("#smoke"), "template", "Treat him as having a smoke pod (normally read from his pylons)."],
        [C("#single") + "  " + C("#pair"), "template", "Always one aircraft / always two."],
        [C("#land") + "  " + C("#sea"), "lane", "Over land or over water (normally worked out from the terrain)."],
    ], [2.35 * inch, 1.15 * inch, W - 3.5 * inch]))
    s.append(Spacer(1, 6))
    s.append(P("You can combine tags: " + C("DAWG Su-33 Sochi #hothead @GAGRA #pair") + " is always a hothead pair on the GAGRA lane."))
    s.append(callout("Big aircraft never do close passes, whatever their tag. That covers the Tu-95/142, Tu-22M3, Tu-160, A-50, "
                     "Il-76/78, An-26 and Su-24MR. They still probe, so a " + C("DAWG Tu-95 #book") + " is a classic Bear run "
                     "down the coast.", NAVY))
    s.append(PageBreak())

    # --------------------------------------------------------------- 4 flags
    s.append(P("4  Flags: controlling DAWG from triggers", "h1"))
    s.append(P("DAWG uses <b>named flags</b>: type the name straight into any Mission Editor flag field. Use them to launch probes "
               "from your own triggers or from F10 radio items, and to react to what happens."))
    s.append(P("Flags DAWG watches (you set them)", "h2"))
    s.append(table([
        ["Flag", "Set it to", "Effect"],
        [C("DAWG_LAUNCH_&lt;LANE&gt;"), "1 \u2013 5", "Launch a probe on that lane now (spaces in the lane name become _). The value picks the pilot."],
        [C("DAWG_LAUNCH"), "1 \u2013 5", "Same, on a random lane."],
        [C("DAWG_PAUSE"), "1 / 0", "1 stops the automatic launches, 0 starts them again. Flag launches still work while paused."],
    ], [1.75 * inch, 0.85 * inch, W - 2.6 * inch]))
    s.append(Spacer(1, 6))
    s.append(table([
        ["Value", "1", "2", "3", "4", "5"],
        ["Pilot", "random", "by-the-book", "showboat", "hothead", "tester"],
    ], [0.8 * inch] + [(W - 0.8 * inch) / 5] * 5))
    s.append(P("DAWG sets the launch flag back to 0 once the probe is up, so the same trigger or radio item can be used again.", "small"))
    s.append(P("Example: a GM control panel in the F10 menu", "h2"))
    s.append(table([
        ["Trigger", "Condition", "Actions"],
        ["ONCE", "TIME MORE 3",
         "ADD RADIO ITEM \u201cHothead on GAGRA\u201d \u2192 flag " + C("DAWG_LAUNCH_GAGRA") + ", value 4<br/>"
         "ADD RADIO ITEM \u201cShowboat on POTI\u201d \u2192 flag " + C("DAWG_LAUNCH_POTI") + ", value 3<br/>"
         "ADD RADIO ITEM \u201cPause probes\u201d \u2192 flag " + C("DAWG_PAUSE") + ", value 1"],
    ], [0.8 * inch, 1.1 * inch, W - 1.9 * inch]))
    s.append(P("Flags DAWG counts up (you read them)", "h2"))
    s.append(P("Each time something happens, DAWG adds 1 to its flag. Use them as conditions: <b>FLAG IS MORE</b> "
               + C("DAWG_ESCORTED_OUT") + " 0 \u2192 MESSAGE TO ALL \u201cGood escort\u201d."))
    s.append(table([
        ["Flag", "Counts", "Flag", "Counts"],
        [C("DAWG_LAUNCHED"), "a probe launched", C("DAWG_ESCORTED_OUT"), "escorted out past 30 NM"],
        [C("DAWG_PROBE"), "he reached his route", C("DAWG_WITHDREW"), "went home with no escort"],
        [C("DAWG_INTERCEPT"), "he was identified", C("DAWG_UNANSWERED"), "a lap nobody responded to"],
        [C("DAWG_SHOW"), "close passes started", C("DAWG_TURNBACK"), "he turned back toward the border"],
        [C("DAWG_FUEL_DUMP"), "a fuel-dump pass", C("DAWG_FIRED_ON"), "someone shot at a probe"],
        [C("DAWG_SHOW_ABORT"), "passes aborted (too close)", C("DAWG_LOST"), "a probe crashed or was shot down"],
    ], [1.65 * inch, 1.8 * inch, 1.65 * inch, W - 5.1 * inch]))
    s.append(P("The F10 GM menu", "h2"))
    s.append(P("The defending side gets <b>F10 \u2192 DAWG (GM)</b> automatically, with these entries:"))
    s += bullets([
        "<b>Status:</b> every probe out, with its pilot, state, response time, who identified it and who escorted it.",
        "<b>Launch a probe now:</b> pick a lane.",
        "<b>Next probe's personality:</b> pick the next pilot.",
        "<b>Pause / resume:</b> automatic launches.",
    ])
    s.append(Spacer(1, 10))

    # ------------------------------------------------------- 5 flying against
    s.append(P("5  Flying against it", "h1"))
    s.append(table([
        ["To", "Do this"],
        ["Identify him", "Get inside <b>2 NM</b>, within <b>1,000 m</b> of his altitude, for <b>10 seconds</b>. OVERLORD calls the ID. "
                         "On land lanes, shadow him from your own side of the border within 15 NM."],
        ["Get a clean show", "Fly <b>straight and level</b>. He formates on you and runs his passes. Hard turns pause the show; "
                             "getting within 50 m of him makes him abort."],
        ["Walk out a hothead", "After his passes he goes back to his probe track. Stay on his wing about 2.5 minutes and he gives up."],
        ["Escort him out", "Stay within <b>3 NM</b> (15 on land) until he's <b>30 NM</b> from the border. You need 60 s of escort to be credited."],
        ["Stop a turnback", "Follow him out. Leave him alone on the way home and a tester will come back, and a hothead might."],
    ], [1.5 * inch, W - 1.5 * inch]))
    s.append(Spacer(1, 8))
    s.append(callout("<b>Weapons tight.</b> Any shot or hit on a probe sends him home at speed, and DAWG logs it "
                     "(" + C("DAWG_FIRED_ON") + "). If you have <b>AI</b> fighters on the defending side, set their ROE to weapon hold, "
                     "or they'll shoot the probes down."))
    s.append(Spacer(1, 12))

    # ---------------------------------------------------------- 6 guard voices
    s.append(Spacer(1, 6))
    s.append(P("6  Talking to them on Guard", "h1"))
    s.append(P("With the <b>DCS-ATC</b> script in the same mission (github.com/ExpertFett/DCS-ATC, with its SRS voice listener "
               "running on the server), the probes <b>talk back</b>. Call them on Guard, <b>243.0</b>, and the probe you're intercepting "
               "answers in a Russian voice, in character, and his pilot type decides whether he does what you say. "
               "DCS-ATC only does the talking; DAWG still flies him. Without DCS-ATC in the mission, nothing changes."))
    s.append(P("What to say (within 5 NM of him, on 243.0)", "h2"))
    s.append(table([
        ["You say", "What happens"],
        ["\u201cSoviet fighter, this is the United States Navy, identify yourself\u201d<br/>or \u201c\u2026state your intentions\u201d",
         "He answers in character (below). Nothing else changes; it's a hail, not an order."],
        ["\u201cTurn left heading two seven zero\u201d<br/>\u201cReverse course\u201d \u00b7 \u201cLeave the area immediately\u201d",
         "An <b>order</b>. He refuses until he's had enough orders for his pilot type, then turns for home."],
        ["\u201cFollow me\u201d", "An order. When he complies he follows you out, except the hothead, who never follows "
                               "(\u201cWe do not follow American aircraft\u201d) but still goes home once he's had enough."],
        ["\u201cLand immediately\u201d", "Always refused. It still counts as an order."],
    ], [2.75 * inch, W - 2.75 * inch]))
    s.append(P("How each pilot answers", "h2"))
    s.append(table([
        ["Pilot", "Answers your hail", "Orders before he goes"],
        ["By-the-book", "\u201c\u2026on a routine patrol in international airspace. State your intentions.\u201d", "<b>1</b>: complies at once"],
        ["Tester", "Same as by-the-book.", "<b>1</b>, but may come back if you don't follow him out"],
        ["Showboat", "\u201cWe see you. Nice aircraft.\u201d", "<b>2</b>: \u201cOne moment, we are not finished here.\u201d"],
        ["Hothead", "\u201cYou are very close. Keep your distance.\u201d", "<b>3</b>: \u201cInternational airspace. We go where we like.\u201d"],
    ], [1.05 * inch, 3.35 * inch, W - 4.4 * inch]))
    s.append(Spacer(1, 6))
    s.append(P("They also talk without being asked: the hothead tells you to back off when you identify him, the showboat says "
               "\u201cwatch this\u201d before his passes, \u201cEnjoy the fuel\u201d comes with the fuel dump, a shot at him gets "
               "\u201cThis will be reported\u201d, and a pilot who's been talking to you announces when he turns for home."))
    s.append(callout("<b>Talking helps walk out a hothead.</b> Once his passes are over and he's back on his probe track, every "
                     "order you give him counts as 30 seconds of escort, on top of sitting on his wing.", NAVY))
    s.append(P("Setting it up", "h2"))
    s += bullets([
        "Load <b>DCS-ATC</b> in the mission as its own instructions say, alongside DAWG. Load order doesn't matter: whichever "
        "loads second finds the other.",
        "Check " + C("dcs.log") + " for " + C("VOICE|on") + ". That line means DAWG and DCS-ATC have connected.",
        "Change his words with " + C("voice_lines") + " in the config, the number of orders with " + C("obeys") + ", or switch it "
        "off with " + C("voice = false") + " (section 8).",
    ])

    # --------------------------------------------------------------- 7 recipes
    s.append(PageBreak())
    s.append(P("7  Recipes: \u201cI want\u2026\u201d", "h1"))
    s.append(table([
        ["I want\u2026", "How"],
        ["Every jet out of one field to be a hothead", "Template name " + C("DAWG Su-27 Sochi #hothead") + "."],
        ["A hothead on the coast at exactly 20 minutes",
         "Trigger ONCE \u00b7 TIME MORE 1200 \u00b7 SET FLAG VALUE " + C("DAWG_LAUNCH_GAGRA") + " = 4."],
        ["Only the probes I launch, none at random",
         "Trigger ONCE \u00b7 TIME MORE 1 \u00b7 SET FLAG VALUE " + C("DAWG_PAUSE") + " = 1. Then launch with flags. "
         "(Or " + C("auto = false") + " in a config.)"],
        ["The GM to pick the pilot live", "F10 \u2192 DAWG (GM) \u2192 Next probe's personality, then Launch a probe now."],
        ["A Bear run down the coast", "Template " + C("DAWG Tu-95 #book @GAGRA") + " (bombers never do passes)."],
        ["One lane to be quiet and professional", "Lane name " + C("DAWG LANE ROKI #book") + "."],
        ["Escalation: calm at first, aggressive later",
         "Lane tagged " + C("#book") + "; at 45 min a trigger sets " + C("DAWG_LAUNCH_GAGRA") + " = 4 three times, a few minutes apart."],
        ["A reward when players do it right", "FLAG IS MORE " + C("DAWG_ESCORTED_OUT") + " 2 \u2192 message / sound / next phase."],
        ["A consequence when they get it wrong",
         "FLAG IS MORE " + C("DAWG_FIRED_ON") + " 0 \u2192 your incident trigger. FLAG IS MORE " + C("DAWG_UNANSWERED") + " 2 \u2192 \u201cthey're getting bolder\u201d."],
        ["Hotheads that take more talking", "Config: " + C("personalities = { hothead = { obeys = 5 } }") + "."],
        ["Quiet probes, even with DCS-ATC in the mission", "Config: " + C("voice = false") + "."],
        ["A hothead that's harder to get rid of, or a new pilot type", "Config file (next section)."],
    ], [2.45 * inch, W - 2.45 * inch]))
    s.append(PageBreak())

    # ------------------------------------------------------------- 8 config
    s.append(P("8  The config file (optional)", "h1"))
    s.append(P("Tags and flags choose <i>which</i> pilot flies. The config file changes <i>how</i> pilots behave and how DAWG runs. "
               "Copy " + C("DAWG_config_template.lua") + " from the zip, uncomment the lines you want, and load it between the "
               "borders file and " + C("DAWG.lua") + ". Every option in it is commented with its default; these are the common ones."))
    s.append(P("Make hotheads harder to walk out, and change the odds", "h2"))
    s.append(code('''
DAWG_CONFIG = {
  personalities = { hothead = { escort_need_s = 300 } },   -- 5 minutes on his wing instead of 2.5
  weights = { book = 30, showboat = 30, hothead = 30, tester = 10 },
}'''))
    s.append(P("A new pilot type", "h2"))
    s.append(code('''
DAWG_CONFIG = {
  personalities = {
    cowboy = { label = "cowboy", depth = 2,           -- starts 2 steps closer
               stunts = { 3, 3 }, opens_with = "sit_six",
               pool = { "sit_six", "canopy_pass", "nose_cross" },
               escort_need_s = 60, turnback = 0.5 },  -- walk him out for 60 s; 50% he turns back
  },
  weights = { book = 40, showboat = 30, hothead = 10, tester = 10, cowboy = 10 },
}'''))
    s.append(P("Tag templates " + C("#cowboy") + " to use it, or launch with flag value 6 (your own pilots are numbered from 6, alphabetically).", "small"))
    s.append(P("A timed script of probes", "h2"))
    s.append(code('''
DAWG_CONFIG = {
  auto = false,                                    -- nothing at random
  schedule = {
    { at = 300,  lane = "GAGRA", personality = "book",    tag = "Act 1" },
    { at = 1500, lane = "GAGRA", personality = "hothead", tag = "Act 2" },
    { at = 2400, lane = "ROKI",  every = { 1200, 1800 } },   -- then every 20-30 min
  },
}'''))
    s.append(P("The tag shows in front of that probe's messages, e.g. [Act 2].", "small"))
    s.append(P("Other settings people change", "h2"))
    s.append(table([
        ["Option", "Default", "What it does"],
        [C("first_s") + ", " + C("interval_s"), "600, {900,1500}", "When the first automatic probe comes, then how often (seconds)."],
        [C("max_active"), "2", "Most automatic probes out at once."],
        [C("floor_nm") + ", " + C("step_nm"), "2, 4", "Closest to the border he ever gets; how much closer each push goes."],
        [C("intercept_nm") + ", " + C("intercept_s"), "2, 10", "What counts as identifying him."],
        [C("release_nm") + ", " + C("escort_credit_s"), "30, 60", "What counts as escorting him out."],
        [C("awacs"), "\"OVERLORD\"", "The callsign that makes the calls."],
        [C("side"), "\"red\"", "Which side probes (set \"blue\" to flip it)."],
        [C("roe"), "4", "The probing side's ROE: 4 = weapon hold, 3 = return fire."],
    ], [2.1 * inch, 1.15 * inch, W - 3.25 * inch]))
    s.append(Spacer(1, 14))

    # --------------------------------------------------------- 9 troubleshoot
    s.append(P("9  Troubleshooting", "h1"))
    s.append(P("DAWG writes every event to " + C("Saved Games\\DCS\\Logs\\dcs.log") + " as lines starting with " + C("DAWG|") + ". "
               "Search the log for them first."))
    s.append(table([
        ["You see", "What it means / what to do"],
        ["Nothing happens at all", "Search the log for " + C("[DAWG] loaded") + " and " + C("Mission script error") + ". Is DAWG.lua loaded <b>last</b>, with DO SCRIPT FILE?"],
        [C("WARN|no templates") + "<br/>" + C("WARN|no lanes"), "Check the names (" + C("DAWG \u2026") + " / " + C("DAWG LANE \u2026") + "), late activation, and that templates are on the probing side."],
        [C("WARN|no borders defined"), "Load the borders file (Caucasus), or draw " + C("DAWG BORDER") + " zones."],
        [C("LANE_WARN|\u2026 only x NM off"), "A lane waypoint is too close to the border. Move it further out."],
        [C("SPAWN_COUNTRY"), "Normal. DAWG swapped to a country the game really puts on the probing side, so the jets come out the right colour."],
        [C("SHOW_STEP|\u2026|timeout"), "He didn't reach one pass position in 45 s. A few are normal. If every pass times out, send the log."],
        [C("STUNT_REJECTED"), "A pass you wrote comes inside 100 m of the target, so DAWG won't fly it."],
        ["No fuel dump", "The template has no white smoke pod, or the type can't carry one (MiG-31)."],
    ], [2.05 * inch, W - 2.05 * inch]))
    s.append(Spacer(1, 4))
    s.append(P("What's in the zip", "h2"))
    s.append(table([
        ["File", "What"],
        [C("DAWG.lua"), "The script. Load it last."],
        [C("DAWG_borders_caucasus.lua"), "Real Caucasus borders (from Natural Earth, public domain)."],
        [C("DAWG_config_template.lua"), "Every option, commented. Optional."],
        [C("examples/DAWG_config_Caucasus.lua"), "A complete config written in Lua instead of the Mission Editor."],
        [C("missions/" + STARTER), "Open in the Mission Editor: everything in this guide, set up."],
        [C("missions/" + DEMO), "Spectate: five intercepts with five different pilots, all AI."],
        [C("MANUAL.md"), "The full technical reference, including the Lua scripting API."],
    ], [3.05 * inch, W - 3.05 * inch]))
    s.append(Spacer(1, 8))
    s.append(callout("<b>Beta.</b> The full probe \u2192 intercept \u2192 passes \u2192 fuel dump \u2192 turnback \u2192 escort-out "
                     "cycle has run in DCS. The formation steering for close passes is new in this version. If passes look wrong, "
                     "send the " + C("SHOW_STEP") + " lines from your dcs.log to github.com/ExpertFett/DAWG/issues.", NAVY))
    s.append(Spacer(1, 8))
    s.append(P("DAWG is free and open source under the MIT licence. Use it, change it and share it; keep the copyright notice.", "small"))

    doc = SimpleDocTemplate(OUT, pagesize=letter, leftMargin=0.8 * inch, rightMargin=0.8 * inch,
                            topMargin=0.75 * inch, bottomMargin=0.75 * inch,
                            title="DAWG User Guide", author="ExpertFett", subject="Dynamic Air Warfare Group for DCS World")
    doc.build(s, onFirstPage=on_page, onLaterPages=on_page)
    print("wrote", OUT)


if __name__ == "__main__":
    build()
