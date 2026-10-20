# Builds docs/BrickGen_Handleiding.pdf (Dutch user manual).
# Run: python3 tools/make_manual.py   (needs reportlab and the DejaVu fonts)
# Update this file when the UI changes, then run it again.

import os
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.enums import TA_LEFT
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (BaseDocTemplate, PageTemplate, Frame, Paragraph, Spacer, Table,
                                TableStyle, PageBreak, KeepTogether, ListFlowable, ListItem)

VERSION = "2026-10-19c"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "BrickGen_Handleiding.pdf")

FONTS = "/usr/share/fonts/truetype/dejavu/"
pdfmetrics.registerFont(TTFont("DV", FONTS + "DejaVuSans.ttf"))
pdfmetrics.registerFont(TTFont("DV-B", FONTS + "DejaVuSans-Bold.ttf"))
pdfmetrics.registerFont(TTFont("DV-I", FONTS + "DejaVuSans.ttf"))
pdfmetrics.registerFont(TTFont("DV-M", FONTS + "DejaVuSansMono.ttf"))
pdfmetrics.registerFontFamily("DV", normal="DV", bold="DV-B", italic="DV-I", boldItalic="DV-B")

BRICK = colors.HexColor("#9c3d26")
INK = colors.HexColor("#222222")
GREY = colors.HexColor("#666666")
LIGHT = colors.HexColor("#f4ece8")
TIPBG = colors.HexColor("#eef4f0")
TIPLINE = colors.HexColor("#3d7a55")
WARNBG = colors.HexColor("#fdf3e3")
WARNLINE = colors.HexColor("#c98a1b")

base = ParagraphStyle("base", fontName="DV", fontSize=9.5, leading=13.5, textColor=INK, alignment=TA_LEFT)
body = ParagraphStyle("body", parent=base, spaceAfter=5)
h1 = ParagraphStyle("h1", parent=base, fontName="DV-B", fontSize=17, leading=21, textColor=BRICK, spaceBefore=4, spaceAfter=8)
h2 = ParagraphStyle("h2", parent=base, fontName="DV-B", fontSize=11.5, leading=15, textColor=INK, spaceBefore=9, spaceAfter=4)
small = ParagraphStyle("small", parent=base, fontSize=8.5, leading=11.5, textColor=GREY)
cell = ParagraphStyle("cell", parent=base, fontSize=8.8, leading=12)
cellb = ParagraphStyle("cellb", parent=cell, fontName="DV-B")
code = ParagraphStyle("code", parent=base, fontName="DV-M", fontSize=8.3, leading=11.5, textColor=INK)


def P(t, s=body):
    return Paragraph(t, s)


def B(t):
    return "<b>" + t + "</b>"


def path(t):
    return '<font name="DV-M" size="8.6">' + t + "</font>"


def steps(items, start=1):
    return ListFlowable([ListItem(P(i, base), leftIndent=16) for i in items], bulletType="1",
                        start=start, bulletFontName="DV-B", bulletFontSize=9.5, bulletColor=BRICK,
                        leftIndent=16, spaceAfter=6)


def bullets(items):
    return ListFlowable([ListItem(P(i, base), leftIndent=12, value="•") for i in items], bulletType="bullet",
                        bulletFontName="DV", bulletColor=BRICK, leftIndent=12, spaceAfter=6)


def box(content, bg, line, title=None):
    inner = []
    if title:
        inner.append(P(B(title), ParagraphStyle("bt", parent=base, textColor=line)))
    for c in content:
        inner.append(P(c, base) if isinstance(c, str) else c)
    t = Table([[inner]], colWidths=[170 * mm])
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), bg),
        ("LINEBEFORE", (0, 0), (0, -1), 3, line),
        ("LEFTPADDING", (0, 0), (-1, -1), 9), ("RIGHTPADDING", (0, 0), (-1, -1), 9),
        ("TOPPADDING", (0, 0), (-1, -1), 6), ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
    ]))
    return KeepTogether([t, Spacer(1, 7)])


def tip(*c):
    return box(c, TIPBG, TIPLINE, "Tip")


def warn(*c):
    return box(c, WARNBG, WARNLINE, "Let op")


def codebox(text):
    t = Table([[P(text, code)]], colWidths=[170 * mm])
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#f2f2f2")),
        ("BOX", (0, 0), (-1, -1), 0.5, colors.HexColor("#cccccc")),
        ("LEFTPADDING", (0, 0), (-1, -1), 8), ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
    ]))
    return KeepTogether([t, Spacer(1, 7)])


def table(rows, widths, header=True):
    data = [[P(c, cellb if (header and r == 0) or (k == 0) else cell) for k, c in enumerate(row)]
            for r, row in enumerate(rows)]
    t = Table(data, colWidths=[w * mm for w in widths], repeatRows=1 if header else 0)
    st = [
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LINEBELOW", (0, 0), (-1, -1), 0.4, colors.HexColor("#dddddd")),
        ("LEFTPADDING", (0, 0), (-1, -1), 5), ("RIGHTPADDING", (0, 0), (-1, -1), 5),
        ("TOPPADDING", (0, 0), (-1, -1), 4), ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
    ]
    if header:
        st += [("BACKGROUND", (0, 0), (-1, 0), LIGHT), ("LINEBELOW", (0, 0), (-1, 0), 0.8, BRICK)]
    t.setStyle(TableStyle(st))
    return t


def section(title, panel_label=None):
    return [P(title, h1)]


# ---------------------------------------------------------------- content
story = []

# cover
story += [Spacer(1, 55 * mm),
          P("BrickGen", ParagraphStyle("t", parent=base, fontName="DV-B", fontSize=40, leading=46, textColor=BRICK)),
          P("Handleiding voor 3ds Max 2026", ParagraphStyle("st", parent=base, fontSize=16, leading=22, textColor=INK)),
          Spacer(1, 6 * mm),
          P("Echte baksteengeometrie op een gevelspline: openingen, dagkanten, verbanden en een "
            "textuur uit één foto van een gevel.", ParagraphStyle("lead", parent=base, fontSize=11, leading=16, textColor=GREY)),
          Spacer(1, 70 * mm),
          P("Polygon · intern gebruik · versie " + VERSION, small),
          PageBreak()]

# contents
story += section("Inhoud")
toc = [
    ("1", "Installeren (eenmalig per pc)"),
    ("2", "Een nieuwe versie installeren"),
    ("3", "Je eerste gevel in 10 stappen"),
    ("4", "Het BrickGen-paneel, knop per knop"),
    ("5", "Texturen: de juiste foto en waar je hem zet"),
    ("6", "Meerdere gevels: instances en kopiëren/plakken"),
    ("7", "Viewport en renderen"),
    ("8", "Een project doorgeven aan een collega"),
    ("9", "Problemen oplossen"),
]
story += [table([[n, t] for n, t in toc], [12, 158], header=False), PageBreak()]

# 1 install
story += section("1. Installeren (eenmalig per pc)")
story += [P("BrickGen bestaat uit een map met scripts en een startbestand dat 3ds Max bij het opstarten laadt. "
            "Bij Polygon staat de map op " + path(r"D:\Tools\Brick-generator") + ". Gebruik overal dezelfde plek, "
            "dan kloppen ook de paden naar de texturen op elke pc.")]
story += [P("De map klaarzetten", h2),
          steps([
              "Kopieer de map " + path(r"D:\Tools\Brick-generator") + " van een collega (netwerkschijf of USB-stick), "
              "of download hem: " + path("github.com/polygon-tools/Brick-generator") + " → groene knop "
              + B("&lt;&gt; Code") + " → " + B("Download ZIP") + ", uitpakken.",
              "Zorg dat de map exact " + path(r"D:\Tools\Brick-generator") + " heet en dat " + path("maxscript") + ", "
              + path("bin") + " en " + path("presets") + " er " + B("rechtstreeks") + " in staan (geen extra submap "
              + path("Brick-generator-main") + ").",
              "Rechtsklik op " + path(r"bin\BrickGen.Core.dll") + " → " + B("Eigenschappen") + ". Staat er onderaan "
              + B("Blokkering opheffen") + "? Aanvinken → " + B("OK") + ". (Windows blokkeert soms gedownloade bestanden.)",
          ])]
story += [P("Het startbestand maken", h2),
          steps([
              "Sluit 3ds Max.",
              "Plak in de adresbalk van Verkenner:",
          ], start=1),
          codebox(r"%LOCALAPPDATA%\Autodesk\3dsMax\2026 - 64bit\ENU\scripts\startup"),
          steps([
              "Rechtsklik op een lege plek → " + B("Nieuw") + " → " + B("Tekstdocument") + ", druk Enter en dubbelklik erop "
              "(het opent in Kladblok).",
              "Plak deze ene regel:",
          ], start=3),
          codebox(r'fileIn @"D:\Tools\Brick-generator\maxscript\BrickGen_Startup.ms"'),
          steps([
              B("Bestand") + " → " + B("Opslaan als...") + ". Zet " + B("Opslaan als type") + " op "
              + B("Alle bestanden (*.*)") + " en typ als naam " + path("BrickGen_Loader.ms") + ". Opslaan.",
              "Verwijder het lege " + path("Nieuw tekstdocument.txt") + ". In de map staat nu "
              + path("BrickGen_Loader.ms") + " (niet " + path("BrickGen_Loader.ms.txt") + ").",
          ], start=5)]
story += [P("Controleren", h2),
          steps([
              "Start 3ds Max en open de " + B("MAXScript Listener") + " (F11).",
              "Daar staat: " + path("BrickGen " + VERSION + r" geladen uit D:\Tools\Brick-generator (snelle C#-module actief)") + ".",
          ]),
          warn("Staat er <b>zonder C#-module</b>, dan is de DLL nog geblokkeerd: zie stap 3 hierboven en herstart Max. "
               "BrickGen werkt dan wel, maar veel trager.",
               "Open altijd eerst Max (met BrickGen geladen) en pas daarna een scène met BrickGen-gevels."),
          PageBreak()]

# 2 update
story += section("2. Een nieuwe versie installeren")
story += [steps([
    "Sluit 3ds Max.",
    "Download de nieuwe ZIP (" + path("github.com/polygon-tools/Brick-generator") + " → " + B("&lt;&gt; Code") + " → "
    + B("Download ZIP") + "). Verwijder eerst oude " + path("Brick-generator-main.zip") + "-bestanden in Downloads, "
    "zo pak je nooit per ongeluk een oude versie uit.",
    "Pak uit, open de map tot je " + path("maxscript") + ", " + path("bin") + "... ziet, selecteer alles (Ctrl+A) en kopieer (Ctrl+C).",
    "Ga naar " + path(r"D:\Tools\Brick-generator") + " (op " + B("D") + ", niet op C) en plak (Ctrl+V) → "
    + B("Bestanden in de map vervangen") + ".",
    "Start Max en kijk in de Listener (F11) naar het versienummer: " + path("BrickGen &lt;datum&gt; geladen uit ...") + ".",
]),
    tip("Je eigen foto's in " + path(r"presets\atlases") + " blijven gewoon staan: bij het plakken worden enkel de "
        "bestanden van BrickGen zelf vervangen."),
    Spacer(1, 6)]

# 3 quick start
story += section("3. Je eerste gevel in 10 stappen")
story += [steps([
    "Teken in het " + B("Front-, Back-, Left- of Right-view") + " de omtrek van de gevel als gesloten " + B("Line") + ".",
    "Ramen en deuren: teken ze als gesloten splines en " + B("Attach") + " ze aan dezelfde spline. Ze worden openingen, net als bij Extrude.",
    "Modify-panel → " + B("Modifier List") + " → " + B("BrickGen") + " (in de plaats van Extrude).",
    "Kijken de stenen naar de verkeerde kant? " + B("Gevel") + " → " + B("Andere kant") + ".",
    B("Steen") + " → kies een " + B("Formaat") + " of vul L / B / H in (mm).",
    B("Verband") + " → kies het verband. Schuif met " + B("Offset X / Y") + " tot de lagen mooi op dorpels en lateien vallen.",
    B("Gevel → Dagkanten → Diepte") + ": de muurdikte (bv. 30 cm). De stenen lopen dan mee in de openingen.",
    B("Steen: textuur en materiaal") + " → " + B("Kies textuur...") + " → kies een foto van een baksteengevel (zie hoofdstuk 5).",
    "Klik " + B("Maak materiaal") + ".",
    "Stel bij " + B("Voeg") + " de voegkleur in en render.",
]),
    tip("Een Rectangle of Circle werkt niet rechtstreeks: zet de vorm eerst om naar een " + B("Editable Spline") + ".",
        "Veel gevels in je scène? Zet " + B("Weergave → Viewport: enkel vlak") + " aan: de viewport blijft vlot en de render toont toch alle stenen."),
    PageBreak()]

# 4 panel
story += section("4. Het BrickGen-paneel, knop per knop")
story += [P("Het paneel bestaat uit blokken (rollouts) van boven naar onder. Hieronder staat per blok wat elke instelling doet.")]
W = [48, 122]
story += [P("Instellingen kopieren / plakken", h2), table([
    ["Instelling", "Wat het doet"],
    ["Kopieer", "Onthoudt alle instellingen van deze gevel, ook de textuur."],
    ["Plak", "Zet de gekopieerde instellingen op deze gevel."],
    ["Plak op alle geselecteerde", "Zelfde, maar op alle geselecteerde BrickGen-gevels tegelijk."],
    ["Met materiaal", "Neemt ook het materiaal mee (voegkleur, glans, relief)."],
], W)]
story += [P("Gevel", h2), table([
    ["Instelling", "Wat het doet"],
    ["Andere kant", "Draait de gevel om, als de stenen naar binnen kijken."],
    ["Seed / Nieuwe", "Bepaalt de toevallige variatie. Zelfde seed = exact dezelfde muur. " + B("Nieuwe") + " geeft een andere variant."],
    ["Dagkanten: Diepte", "Hoe diep de stenen in de openingen (en de muur) lopen: meestal de muurdikte."],
    ["Offset zijkant", "Verschuift het verband in de zijkanten van de openingen, tot ze mooi aansluiten op de gevel."],
    ["Ook langs de buitenrand", "Maakt ook stenen aan de buitenrand van de gevel (hoeken van het gebouw)."],
    ["Dikte naar voren", "De dikte gaat naar voren, net als Extrude (standaard aan)."],
], W)]
story += [P("Verband", h2), table([
    ["Instelling", "Wat het doet"],
    ["Verband", "Halfsteens, Staand (stapel), Vlaams, Kruisverband of Wild."],
    ["Offset X / Offset Y", "Verschuift het steenraster horizontaal / verticaal (mm), bv. zodat een lintvoeg op de hoogte van een dorpel valt."],
    ["90 graden gedraaid", "Zet het hele verband rechtop. Staand (stapel) + deze optie = verticaal stapelverband."],
], W)]
story += [P("Steen", h2), table([
    ["Instelling", "Wat het doet"],
    ["Formaat", "Kies een bekend steenformaat; L, B en H worden ingevuld."],
    ["Lengte / Breedte / Hoogte", "Maat van één steen in mm. Moet overeenkomen met de stenen op je textuurfoto."],
], W)]
story += [P("Steen: textuur en materiaal", h2), table([
    ["Instelling", "Wat het doet"],
    ["Kies textuur...", "Kies een foto (jpg/png/tif) van een baksteengevel. BrickGen zoekt zelf de stenen in de foto."],
    ["Geen", "Haalt de textuur weg."],
    ["Stenen controleren...", "Toont de foto met een kader rond elke gevonden steen (groen = strek, blauw = kop). Klik op een "
                              "lelijke of verkeerd herkende steen om hem uit te zetten (rood) en klik " + B("Opslaan") + "."],
    ["Textuur herladen", "Na het aanpassen van de foto (bv. in Photoshop): zoekt de stenen opnieuw, ververst de foto in het "
                         "materiaal en bouwt alle gevels met die foto opnieuw op. Max merkt een gewijzigd bestand niet vanzelf."],
    ["Random spiegelen / 180 graden", "Meer variatie: stenen uit de foto worden willekeurig gespiegeld of omgedraaid."],
    ["Glans / Relief", "Glans en bump van de steen. Past het materiaal meteen aan, zonder de gevel opnieuw te bouwen."],
    ["Maak materiaal", "Maakt een Multi/Sub-materiaal (V-Ray, anders Physical) en geeft het aan de gevel(s)."],
    ["Steen-ID's / Voeg-ID", "Material ID's: stenen krijgen 1..N, de voeg 100. Enkel aanpassen voor een eigen materiaal."],
], W)]
story += [P("Steen: vorm en imperfectie", h2), table([
    ["Instelling", "Wat het doet"],
    ["Afronding (+ variatie)", "Afgeronde randen van de stenen in mm, met wat variatie per steen."],
    ["Hoeken / Diepte / Rotatie / Maat", "Kleine onregelmatigheden per steen: scheve hoeken, iets verder naar voren of achter, "
                                         "een beetje gedraaid, iets groter of kleiner."],
    ["Afgebroken hoekjes", B("Stenen (%)") + ": hoeveel stenen een afgebroken hoekje hebben. " + B("Grootte") + ": hoe groot."],
], W)]
story += [P("Voeg", h2), table([
    ["Instelling", "Wat het doet"],
    ["Lintvoeg / Stootvoeg", "Dikte van de horizontale / verticale voeg in mm."],
    ["Terugligging", "Hoe ver de voeg achter de stenen ligt."],
    ["Voegvlak", "Het vlak achter de stenen (de voeg) aan of uit."],
    ["Kleur", "Voegkleur. Je kan ook een kleurcode plakken in het kleurvenster. Past het materiaal meteen aan."],
    ["Relief", "Fijne korrel (bump) in de voeg."],
], W)]
story += [P("Weergave", h2), table([
    ["Instelling", "Wat het doet"],
    ["Snelle preview", "Stenen zonder afronding en variatie: sneller tijdens het instellen."],
    ["Viewport: enkel vlak", "De viewport toont enkel een blok zoals Extrude (omtrek, openingen, dikte). Bij het renderen verschijnen de stenen automatisch."],
], W), PageBreak()]

# 5 textures
story += section("5. Texturen: de juiste foto en waar je hem zet")
story += [P("Een goede foto", h2),
          bullets([
              "Recht en vlak gefotografeerd, zonder perspectief: de lagen lopen horizontaal.",
              "Zelfde steenformaat als ingesteld bij " + B("Steen") + ". BrickGen gebruikt dat om de stenen in de foto te herkennen.",
              "Hoe groter en scherper, hoe beter. Lichte en donkere voegen werken allebei.",
              "Een normal- of roughness-map met dezelfde naam + " + path("_normal") + " / " + path("_rough") + " ernaast wordt automatisch mee gebruikt.",
          ]),
          P("Waar zet je de foto?", h2),
          P("Zet je baksteenfoto's in " + path(r"D:\Tools\Brick-generator\presets\atlases") + ". Die map heeft iedereen op "
            "dezelfde plek, zodat scènes ook bij collega's de foto terugvinden."),
          warn("Gebruik geen foto op je Bureaublad of in Downloads: in dat pad zit jouw gebruikersnaam, waardoor het op een "
               "andere pc nooit klopt."),
          P("Wat gebeurt er als je een foto kiest?", h2),
          P("De eerste keer zoekt BrickGen de stenen in de foto (enkele seconden). Het resultaat komt naast de foto als "
            + path("foto.brickgen.json") + "; daarna gaat het meteen. Dat bestand bewaart ook de stenen die je bij "
            + B("Stenen controleren") + " hebt uitgezet. Kopieer het dus altijd mee met de foto."),
          P("Een foto aanpassen", h2),
          steps([
              "Pas de foto aan (bv. kleur in Photoshop) en sla hem op " + B("onder dezelfde naam") + ".",
              "Selecteer een gevel met die textuur en klik " + B("Textuur herladen") + ".",
              "Alle gevels en materialen met die foto worden bijgewerkt. Uitgezette stenen blijven uit zolang ze op dezelfde plek gevonden worden.",
          ]),
          PageBreak()]

# 6 multiple
story += section("6. Meerdere gevels: instances en kopiëren/plakken")
story += [P("Optie A: instance (gevels altijd gelijk)", h2),
          steps([
              "Rechtsklik in de modifier stack op " + B("BrickGen") + " → " + B("Copy") + ".",
              "Selecteer een andere gevelspline → rechtsklik in de modifier stack → " + B("Paste Instanced") + ".",
          ]),
          P("Elke gevel houdt zijn eigen vorm, maar een instelling aanpassen verandert ze allemaal tegelijk. "
            + B("Maak materiaal") + " geldt dan ook voor alle gevels."),
          P("Optie B: kopiëren en plakken (gevels los van elkaar)", h2),
          steps([
              "Stel één gevel volledig in.",
              "Klik bovenaan de modifier op " + B("Kopieer") + ".",
              "Selecteer de andere gevels en klik " + B("Plak op alle geselecteerde") + " (met " + B("Met materiaal") + " aangevinkt voor hetzelfde materiaal).",
          ]),
          P("Daarna kan je elke gevel nog apart bijstellen. Het kopiëren werkt ook tussen twee scènes en na een herstart van Max "
            "(dan zonder materiaal)."),
          warn("Plakken neemt " + B("alle") + " instellingen over: ook steenformaat, verband, offsets en dagkanten."),
          Spacer(1, 4)]

# 7 viewport
story += section("7. Viewport en renderen")
story += [bullets([
    B("Snelle preview") + ": eenvoudige stenen tijdens het instellen. Zet uit voor de render.",
    B("Viewport: enkel vlak") + ": per gevel een blok in de viewport, stenen enkel in de render.",
    "Knop " + B("Stenen aan/uit") + " voor alle gevels tegelijk: " + B("Customize → Customize User Interface") + " → categorie "
    + B("BrickGen") + " → sleep " + B("Stenen aan/uit") + " naar een toolbar of geef het een sneltoets.",
]),
    warn("V-Ray IPR en ActiveShade tonen bij " + B("enkel vlak") + " het blok, niet de stenen. Zet de optie daarvoor uit."),
    tip("Verschillen per viewport (bv. stenen enkel in de camera) kan 3ds Max niet voor één object: gebruik de knop "
        + B("Stenen aan/uit") + " om snel te wisselen."),
    PageBreak()]

# 8 colleague
story += section("8. Een project doorgeven aan een collega")
story += [steps([
    "Zorg dat de textuurfoto's in " + path(r"D:\Tools\Brick-generator\presets\atlases") + " staan (met hun "
    + path(".brickgen.json") + "). Stond een foto ergens anders? Verplaats hem daarheen en kies hem per gevel opnieuw met "
    + B("Kies textuur...") + ". Sla de scène op.",
    "Kopieer jouw volledige map " + path(r"D:\Tools\Brick-generator") + " naar " + path(r"D:\Tools\Brick-generator")
    + " op de pc van je collega. De foto's gaan zo automatisch mee.",
    "Heeft je collega BrickGen nog niet? Volg dan hoofdstuk 1 (startbestand maken, DLL deblokkeren).",
    "Je collega start Max, controleert de Listener (F11) en opent daarna de scène.",
]),
    P("Ontbreekt toch een textuur?", h2),
    bullets([
        B("Materiaal") + ": " + B("File → Reference → Asset Tracking") + " → selecteer de ontbrekende bestanden → rechtsklik → "
        + B("Set Path...") + " → kies de juiste map.",
        B("BrickGen") + ": per gevel " + B("Kies textuur...") + " en de foto opnieuw kiezen (Asset Tracking past het pad in BrickGen niet aan).",
    ]),
    PageBreak()]

# 9 troubleshooting
story += section("9. Problemen oplossen")
story += [table([
    ["Probleem", "Oplossing"],
    ["BrickGen staat niet in de Modifier List", "Kijk in de Listener (F11) of er " + path("BrickGen ... geladen") + " staat. Zo niet: "
     "controleer het startbestand (hoofdstuk 1) en of het pad naar " + path(r"D:\Tools\Brick-generator") + " klopt."],
    ["\"fileIn: can't open file\" bij het opstarten", "De map staat niet op de juiste plek of heet anders (bv. "
     + path("Brick-generator-main") + " of een extra submap). Hernoem/verplaats tot " + path(r"D:\Tools\Brick-generator\maxscript") + " bestaat."],
    ["\"zonder C#-module\" in de Listener", "Rechtsklik " + path(r"bin\BrickGen.Core.dll") + " → Eigenschappen → Blokkering opheffen → herstart Max."],
    ["Nieuwe knoppen zijn niet te zien na een update", "De nieuwe bestanden staan op de verkeerde schijf of het was een oude ZIP. "
     "Controleer het versienummer in de Listener en volg hoofdstuk 2 opnieuw."],
    ["Stenen kijken naar binnen", B("Gevel → Andere kant") + "."],
    ["De gevel blijft vlak in de viewport", B("Weergave → Viewport: enkel vlak") + " staat aan (of de knop " + B("Stenen aan/uit") + "). Render toont wel stenen."],
    ["Geen stenen gevonden in de foto", "Foto recht en zonder perspectief? Komt het steenformaat bij " + B("Steen") + " overeen met de foto?"],
    ["Rare stenen of voeg in de steen", B("Stenen controleren...") + " → klik de foute stenen weg → " + B("Opslaan") + "."],
    ["Foto aangepast maar niets veranderd", B("Textuur herladen") + "."],
    ["Lagen sluiten niet aan op dorpel of buurgevel", B("Verband → Offset Y") + " (en " + B("Offset X") + " voor de stootvoegen)."],
    ["Zijkanten van openingen sluiten niet mooi aan", B("Gevel → Dagkanten → Offset zijkant") + "."],
    ["Een foutmelding", "Kopieer de volledige tekst uit de Listener (F11) en bezorg ze aan wie BrickGen onderhoudt."],
], [60, 110])]


# keep a sub heading on the same page as the table or list below it
merged = []
for f in story:
    if merged and isinstance(merged[-1], Paragraph) and merged[-1].style is h2 and isinstance(f, (Table, ListFlowable)):
        merged[-1] = KeepTogether([merged[-1], f])
    else:
        merged.append(f)
story = merged


# ---------------------------------------------------------------- layout
def on_page(canv, doc):
    canv.saveState()
    if doc.page > 1:
        canv.setFillColor(BRICK)
        canv.rect(20 * mm, A4[1] - 14 * mm, 170 * mm, 0.8, stroke=0, fill=1)
        canv.setFont("DV", 8)
        canv.setFillColor(GREY)
        canv.drawString(20 * mm, A4[1] - 12 * mm, "BrickGen · handleiding")
        canv.drawRightString(190 * mm, 10 * mm, str(doc.page))
    else:
        canv.setFillColor(BRICK)
        canv.rect(0, A4[1] - 18 * mm, A4[0], 18 * mm, stroke=0, fill=1)
        # small brick band
        y = 30 * mm
        canv.setFillColor(colors.HexColor("#b4583f"))
        for row in range(4):
            off = 0 if row % 2 == 0 else 13 * mm
            x = 20 * mm - off
            while x < 190 * mm:
                x0, x1 = max(x, 20 * mm), min(x + 24 * mm, 190 * mm)
                if x1 > x0:
                    canv.rect(x0, y + row * 7 * mm, x1 - x0, 5.6 * mm, stroke=0, fill=1)
                x += 26 * mm
    canv.restoreState()


os.makedirs(os.path.dirname(OUT), exist_ok=True)
doc = BaseDocTemplate(OUT, pagesize=A4, leftMargin=20 * mm, rightMargin=20 * mm, topMargin=20 * mm,
                      bottomMargin=18 * mm, title="BrickGen - Handleiding", author="Polygon",
                      subject="BrickGen voor 3ds Max 2026")
frame = Frame(doc.leftMargin, doc.bottomMargin, doc.width, doc.height, id="f")
doc.addPageTemplates([PageTemplate(id="p", frames=[frame], onPage=on_page)])
doc.build(story)
print(OUT)
