# BrickGen (werktitel)

Parametrische baksteengevel voor 3ds Max: echte geometrie in plaats van een bitmap met displacement.
Volledige specificatie en planning: [PLAN.md](PLAN.md).

**Status:** fase 1 (MVP rechte muur) is gecodeerd en moet nog in 3ds Max getest worden.

## Vereisten

| | Minimum (voorstel, zie PLAN.md §16) |
|---|---|
| 3ds Max | 2022 of nieuwer (de code heeft minstens 2017.1 nodig, voor `Dictionary` en `Integer64`) |
| V-Ray | 6 of nieuwer (pas nodig vanaf fase 2, voor "Maak materiaal") |

## Installatie

1. Clone of kopieer deze repo naar een vaste plaats (lokaal of op de gedeelde schijf), bv. `D:\Tools\Brick-generator`.
2. Maak in je startup-map van 3ds Max een bestand `BrickGen_Loader.ms`.
   Pad: `%LOCALAPPDATA%\Autodesk\3dsMax\<versie> - 64bit\ENU\scripts\startup\`.
   Zet er deze regel in:
   ```maxscript
   fileIn @"D:\Tools\Brick-generator\maxscript\BrickGen_Startup.ms"
   ```
3. Herstart 3ds Max. In de MAXScript Listener verschijnt `BrickGen geladen uit ... (snelle C#-module actief)`.
   Staat er *zonder C#-module*: rechtsklik op `bin\BrickGen.Core.dll` → *Eigenschappen* → vink *Blokkering opheffen* aan (Windows blokkeert soms gedownloade DLL's) en herstart Max. BrickGen werkt ook zonder, maar veel trager.

Het laden moet via de startup-map gebeuren: een scène met BrickWall-objecten kan pas geopend worden als de plugin al gedefinieerd is.

## Gebruik

### Als modifier op een gevel-spline (aanbevolen)
1. Plaats het gevelplan en teken in het **Front-, Back-, Left- of Right-view** de omtrek van de gevel als gesloten **Line** / **Editable Spline**.
2. Ramen en deuren: teken ze als extra gesloten splines **in hetzelfde object** (Attach). Ze worden openingen, zoals bij Extrude.
3. Modify-panel → **Modifier List** → **BrickGen** (in de plaats van Extrude). Het hele vlak wordt baksteen; stenen worden afgezaagd aan alle randen.
4. De stenen kijken naar het view waarin je tekende. Verkeerde kant: vink **Andere kant** aan.
5. **Dagkanten → Diepte** (bv. 30 of 40 cm): langs elke horizontale/verticale rand van een opening komt een strook bakstenen de muur in, met dezelfde laaghoogtes als de gevel. Met **Ook langs de buitenrand** gebeurt dat ook aan de buitenkant van de gevel (hoeken van het gebouw).
4b. **Dikte naar voren (zoals Extrude)** (in *Gevel → Dagkanten*, standaard aan bij nieuwe modifiers): de gevel ligt op *Diepte* vóór het splinevlak en de dagkanten lopen van het splinevlak naar voren, zoals een Extrude van dezelfde spline.
4c. **Weergave → Viewport: enkel vlak**: in de viewports alleen een eenvoudig blok zoals Extrude (exact de omtrek van de spline, de openingen en de dikte), bij het renderen automatisch alle stenen. Voor alle gevels tegelijk: knop **Stenen aan/uit** (*Customize → Customize User Interface → categorie BrickGen*, sleep naar een toolbar of geef een sneltoets). Let op: V-Ray IPR/ActiveShade toont dan het vlak; zet het daarvoor uit.
5a. **Verband → Offset X / Offset Y** (mm): verschuift het steenraster horizontaal / verticaal, bv. zodat een lintvoeg precies op de hoogte van een dorpel of van de buurgevel valt.
5b. **Verband → 90 graden gedraaid (staande stenen)**: het hele verband staat rechtop, bv. *Staand (stapel)* + deze optie = verticaal stapelverband. Werkt met elk verband, ook met textuur en dagkanten.
6. **Offset zijkant** (in *Gevel → Dagkanten*): verschuift het verband van de stenen in de zijkanten van de openingen (gemeten vanaf de voorkant van de gevel). Pas aan tot de stenen in de dagkant mooi aansluiten op de gevel; de gevel zelf stel je in met **Offset X / Offset Y**.

7. **Textuur**: in *Steen: textuur en materiaal* → **Kies textuur...** en kies gewoon een **foto (jpg/png/tif)** van een baksteengevel, recht en vlak gefotografeerd, met hetzelfde steenformaat als bij *Steen*. BrickGen zoekt zelf de stenen in de foto (enkele seconden, de eerste keer) en bewaart dat naast de foto als `foto.brickgen.json`; daarna gaat het meteen. Elke steen krijgt een willekeurige steen uit de foto (koppen een kop, afgezaagde stenen een deel), optioneel gespiegeld of 180° gedraaid. Een normal/roughness-map met dezelfde naam + `_normal` / `_rough` wordt automatisch mee gebruikt. Een bestaande atlas (`.json`) kiezen kan ook. Met **Stenen controleren...** zie je de foto met een kader rond elke gevonden steen (groen = strek, blauw = kop); klik op een verkeerd herkende of lelijke steen om hem uit te zetten (rood) en klik **Opslaan**. Heb je de foto zelf aangepast (bv. in Photoshop)? Klik dan **Textuur herladen**: BrickGen zoekt de stenen opnieuw, ververst de foto in het materiaal en bouwt alle gevels met die foto opnieuw op (3ds Max merkt een gewijzigd bestand niet vanzelf). Uitgezette stenen blijven uit zolang ze op dezelfde plek gevonden worden; verander je het steenformaat, dan wordt ook opnieuw gezocht. Boven- en onderkant van een opening (dorpel/latei) tonen het legvlak van de stenen: de eerste rij loopt door met de stenen van de gevel erboven of eronder. Daarna **Maak materiaal**: Multi/Sub-materiaal met V-Ray (of Physical Material zonder V-Ray), ID 1..N = stenen, ID 100 = voeg. **Glans** en **Relief** (bij de steen), **Kleur** en **Relief** (bij *Voeg*) (bump: de steenfoto zelf en een fijne korrel op de voeg) passen een al gemaakt materiaal meteen aan, zonder de geometrie opnieuw te bouwen.

Het resultaat wordt gecachet: zolang spline en parameters niet veranderen, wordt de geometrie niet opnieuw berekend.

Beperkingen van deze eerste versie: segmenten worden als rechte lijnen tussen de knooppunten behandeld (bogen nog niet); schuine randen (puntgevel) worden per laag verticaal afgezaagd, in kleine trapjes. De modifier moet rechtstreeks op de Line of Editable Spline staan, niet op een Rectangle; zet die eerst om naar een Editable Spline.

### Instellingen kopiëren naar andere gevels
Bovenaan de modifier: **Kopieer** neemt alle instellingen (ook de textuur) van deze gevel; **Plak** zet ze op een andere BrickGen-gevel, **Plak op alle geselecteerde** op alle geselecteerde gevels tegelijk. Met **Met materiaal** krijgen ze ook hetzelfde materiaal (voegkleur, glans, relief). De instellingen worden ook in een bestand in de temp-map bewaard: plakken werkt dus ook in een andere scène of na een herstart (dan zonder materiaal).

### Als losse muur (object)

- **Create-panel → Geometry → BrickGen → BrickWall.** Klik het startpunt aan, sleep voor de lengte, beweeg de muis voor de hoogte en klik om te bevestigen.
- Of via een knop: *Customize → Customize User Interface → categorie "BrickGen" → BrickWall*.
- De voorkant van de muur kijkt naar **−Y** (in het top-view: naar onder). Het draaipunt ligt linksonder aan de voorkant.

### Parameters (zie PLAN.md §6)

| Rollout | Wat |
|---|---|
| Muur | lengte, hoogte, seed (+ knop "Nieuwe seed") |
| Steen | formaat-preset (uit `presets/formats.json`), L / B / H in mm |
| Voeg | lintvoeg, stootvoeg, terugligging, voegvlak aan/uit |
| Verband | halfsteens, staand, Vlaams, kruisverband, wild; startoffset |
| Vorm en imperfectie | chamfer (+ variatie), hoek-, diepte-, rotatie- en maatvariatie |
| Materiaal | aantal random steen-ID's (1..N), ID van de voeg |
| Weergave | snelle preview zonder chamfer en jitter |

### UV-kanalen

| Kanaal | Inhoud |
|---|---|
| 1 | Per steen 0–1 over de volledige steen. Afgezaagde stenen krijgen een deel daarvan. Vanaf fase 2 wordt dit naar een cel van een atlas gemapt. |
| 2 | Planair over de hele muur in echte maat (1 UV-eenheid = 1 m). Gebruik dit voor vuil en grunge, voor de voeg, of voor een gewone tegelende baksteentextuur. |

Tot het materiaal er is (fase 2): een Multi/Sub-Object met ID's 1..N voor de stenen en ID 100 voor de voeg werkt meteen. Voor variatie per steen gebruik je *VRayMultiSubTex* of *VRayColorCorrection* met de modus "random by render ID/element": elke steen is een apart mesh-element.

## Testen

In een lege scène, na het laden:

- `testscenes/BrickGen_Tests.ms` (*Scripting → Run Script*) controleert determinisme, het aantal tris per steen, material ID's, randgevallen, eenheden (mm/cm/m) en bouwtijden. De resultaten (PASS/FAIL + tijden) komen in de Listener; plak die output in een GitHub Issue of in de chat.
- `testscenes/BrickGen_MakeTestScene.ms` maakt `testscenes/test_gevel.max` aan, met camera, licht, grondvlak en een testmuur.
- Bouwtijd van elke muur loggen: `BrickGenSettings.logTiming = true` in de Listener. Builds trager dan 500 ms worden altijd gelogd.

## Repo-structuur

Zie PLAN.md §3. Kort samengevat: `maxscript/` bevat de plugin, `presets/` de formaten en atlassen, `testscenes/` de test- en scènescripts, en `webtool/` de atlas-editor (fase 3).
