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

1. Clone of kopieer deze repo naar een vaste plaats (lokaal of op de gedeelde schijf), bv. `P:\Tools\BrickGen`.
2. Maak in je startup-map van 3ds Max een bestand `BrickGen_Loader.ms`.
   Pad: `%LOCALAPPDATA%\Autodesk\3dsMax\<versie> - 64bit\ENU\scripts\startup\`.
   Zet er deze regel in:
   ```maxscript
   fileIn @"P:\Tools\BrickGen\maxscript\BrickGen_Startup.ms"
   ```
3. Herstart 3ds Max. In de MAXScript Listener verschijnt `BrickGen geladen uit ...`.

Het laden moet via de startup-map gebeuren: een scène met BrickWall-objecten kan pas geopend worden als de plugin al gedefinieerd is.

## Gebruik

### Als modifier op een spline (aanbevolen)
1. Teken een **Line** of **Editable Spline** (bv. de buitenkant van de gevel, over een plan).
2. Modify-panel → **Modifier List** → **BrickGen** (in de plaats van Extrude).
3. Stel de **Hoogte** in. Elk recht segment wordt een muur; het verband loopt door over de hoeken.
4. De spline is de **buitenkant** van de gevel. Staan de stenen aan de verkeerde kant: vink **Andere kant** aan.

Beperkingen van deze eerste versie: segmenten worden als rechte lijnen tussen de knooppunten behandeld (bogen nog niet). Hoeken krijgen nog geen echt hoekverband (fase 4). De modifier moet rechtstreeks op de Line of Editable Spline staan, niet op een Rectangle of Circle; zet die eerst om naar een Editable Spline.

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
