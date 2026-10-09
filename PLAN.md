# BrickGen — parametrische baksteengevel voor 3ds Max (werktitel)

> Projectplan en technische specificatie. Dit document is de bron van waarheid voor de ontwikkeling.
> Lees het volledig voor je code schrijft. Werk fase per fase en vink de acceptatiecriteria af.

---

## 1. Doel

Een gratis, interne 3ds Max-tool voor ons bureau die baksteengevels als **echte geometrie** genereert, in plaats van een bitmap met displacement. Later eventueel uitbreiden en verkopen.

### Problemen die we oplossen
1. **Repetitie** in gevels wanneer één tegelende bitmap gebruikt wordt.
2. **Displacement** is moeilijk in te stellen omdat je het resultaat pas bij het renderen ziet. Met echte geometrie zie je stenen, chamfers en terugliggende voegen meteen in de viewport.
3. **Losse bakstenen** zijn moeilijk te vinden als aparte texturen. Oplossing: we gebruiken een bestaande bakstenentextuur als **atlas** en elke steen pakt een willekeurige steen uit die textuur.

### Niet-doelen (voorlopig)
- Geen ondersteuning voor andere renderers dan V-Ray (Corona eventueel later).
- Geen gebogen muren in de eerste versies.
- Geen online backend en geen accounts.

---

## 2. Belangrijke beslissingen

| Onderwerp | Keuze | Reden |
|---|---|---|
| Taal plugin | **MAXScript scripted plugin** (`plugin simpleObject`) | Echt parametrisch object in het Create-panel; past live aan bij parameterwijziging. Python/pymxs kan dit niet eenvoudig. |
| Geometrie | **Eén mesh** per muur (eventueel opgesplitst in chunks) | Duizenden losse nodes (ook instances) maken Max traag. Eén mesh van 1–2M tris is geen probleem. |
| Texturering | **UV-atlas** op de bronstextuur | Geen losse PNG's nodig; normal/roughness/bump blijven automatisch kloppen op dezelfde UV's. |
| Webtool | Statische HTML/JS/canvas, gehost op **GitHub Pages** | Geen server nodig, gratis. |
| Versiebeheer | **GitHub**, private repo | Historiek, releases, samenwerken. |
| Backend (Supabase e.d.) | **Niet nodig** voor intern gebruik | Presets en atlassen zijn JSON-bestanden op de gedeelde schijf. Pas overwegen bij verkoop (online bibliotheek). |
| Licenties bij verkoop | Lemon Squeezy of Gumroad license-key API | Eenvoudiger dan zelf bouwen. |
| Eenheden intern | **millimeter** | Bij het bouwen omrekenen naar systeemeenheden van de scène (`units.decodeValue` / schaalfactor). |

---

## 3. Repo-structuur

```
brickgen/
├── PLAN.md                  ← dit document
├── CLAUDE.md                ← korte werkinstructies voor Claude Code (verwijst naar PLAN.md)
├── README.md                ← installatie en gebruik voor collega's
├── maxscript/
│   ├── BrickGen_Object.ms   ← scripted plugin (simpleObject) — losse rechte muur
│   ├── BrickGen_Modifier.ms ← scripted modifier (simpleMeshMod) — vult een gevel-spline met baksteen
│   ├── BrickGen_Region.ms   ← 2D-regio: binnen-intervallen per hoogte (omtrek + openingen)
│   ├── BrickGen_Bonds.ms    ← verbanddefinities (data + functies)
│   ├── BrickGen_Mesh.ms     ← geometrie-opbouw (steen, voeg, chamfer, jitter)
│   ├── BrickGen_UV.ms       ← atlas-UV's en extra UV-kanalen
│   ├── BrickGen_Material.ms ← automatisch V-Ray-materiaal opbouwen
│   ├── BrickGen_Atlas.ms    ← atlas-JSON inlezen (fase 2)
│   ├── BrickGen_Json.ms     ← kleine JSON-parser zonder externe afhankelijkheden
│   ├── BrickGen_Presets.ms  ← formats.json inlezen (met ingebouwde fallback)
│   ├── BrickGen_RNG.ms      ← deterministische random met seed
│   └── BrickGen_Startup.ms  ← laadt alles, registreert macroscripts
├── webtool/
│   ├── index.html           ← atlas-editor
│   ├── app.js
│   └── style.css
├── presets/
│   ├── formats.json         ← steenformaten
│   └── atlases/             ← atlas-JSON's per textuur
├── testscenes/
│   ├── BrickGen_MakeTestScene.ms ← bouwt test_gevel.max (bron van de testscène)
│   ├── BrickGen_Tests.ms    ← automatische checks fase 1 (determinisme, randen, eenheden, timing)
│   └── test_gevel.max       ← vaste testscène (zie §12 fase 0)
├── docs/
│   └── screenshots/
└── dist/                    ← gebouwde .mzp-pakketten
```

---

## 4. Terminologie (Nederlands ↔ code)

| Nederlands | Code-naam | Betekenis |
|---|---|---|
| strek | `stretcher` | steen met de lange zijde (L) zichtbaar |
| kop | `header` | steen met de korte zijde (B) zichtbaar |
| klezoor | `closer` | stuk steen (vaak ¼ of ¾) om het verband aan een hoek/einde te laten kloppen |
| lintvoeg | `bedJoint` | horizontale voeg |
| stootvoeg | `headJoint` | verticale voeg |
| laag | `course` | één rij stenen |
| verband | `bond` | legpatroon |
| rollaag | `soldierCourse` / `rowlock` | staande of op kant gelegde stenen boven openingen |
| terugliggende voeg | `jointRecess` | hoe diep de voeg achter het steenvlak ligt |

---

## 5. Coördinatenstelsel en conventies

- Muur-lokale assen: **X** = langs de muur, **Z** = omhoog, **Y** = diepte. Het steenvlak (voorkant) ligt op **y = 0**, de muur "gaat de diepte in" richting +Y. Normale van de voorkant wijst naar **−Y**.
- Oorsprong van het object: linksonder aan de voorkant van de muur.
- Alle maten in mm, omzetten bij het bouwen.
- Alle randomisatie via een **eigen seed-RNG** (`BrickGen_RNG.ms`), nooit via de globale `random` zonder seed. Zelfde parameters + zelfde seed = exact dezelfde muur.
- Elke steen krijgt een eigen index `i`; random waarden worden afgeleid van `hash(seed, i, kanaal)` zodat het toevoegen van een nieuwe random-parameter de bestaande willekeur niet verschuift.
  Implementatie: één hash per kanaal levert drie waarden (10/10/11 bits, `BrickGenRNG.u01x3`). Kanaalindeling staat bij `addBrick` in `BrickGen_Mesh.ms`.

---

## 6. Parameters van het object

### Muur
| Parameter | Type | Default | Opmerking |
|---|---|---|---|
| `wallLength` | worldUnits | 3000 mm | |
| `wallHeight` | worldUnits | 2500 mm | |
| `seed` | integer | 12345 | |

### Steen
| Parameter | Type | Default | Opmerking |
|---|---|---|---|
| `brickL` | float mm | 210 | lengte |
| `brickB` | float mm | 100 | breedte (zichtbaar bij koppen) |
| `brickH` | float mm | 50 | hoogte |
| `formatPreset` | dropdown | Waalformaat | vult L/B/H in vanuit `formats.json` |

Voorbeelden voor `formats.json` (nakijken bij fabrikant): Waalformaat 210×100×50, Dikformaat 210×100×65, Vechtformaat 210×100×40, Modulair 190×90×50.

### Voeg
| Parameter | Type | Default |
|---|---|---|
| `bedJoint` | float mm | 12 |
| `headJoint` | float mm | 12 |
| `jointRecess` | float mm | 5 |
| `mortarEnabled` | bool | true |

### Verband
| Parameter | Type | Default |
|---|---|---|
| `bondType` | dropdown | halfsteens |
| `startOffset` | float mm | 0 | horizontale verschuiving van het hele patroon |

### Vorm en imperfectie
| Parameter | Type | Default | Opmerking |
|---|---|---|---|
| `chamfer` | float mm | 2 | afronding/afschuining van de voorrand |
| `chamferJitter` | float 0–1 | 0.3 | variatie van de chamfer per steen |
| `cornerJitter` | float mm | 1.0 | random verschuiving van de 8 voorste hoekpunten |
| `depthJitter` | float mm | 1.5 | steen ligt iets voor/achter het vlak |
| `rotJitter` | float graden | 0.3 | lichte rotatie rond Y |
| `sizeJitter` | float mm | 1.0 | lengte/hoogte-variatie |
| `damagedPct` | float % | 0 | (fase 5) percentage afgebrokkelde stenen |

### Materiaal en UV
| Parameter | Type | Default |
|---|---|---|
| `matIdCount` | integer | 5 | aantal random material ID's voor stenen (1..N) |
| `mortarMatId` | integer | 100 |
| `atlasFile` | filename | — | pad naar atlas-JSON |
| `atlasFlip` | bool | true | random spiegelen toestaan |
| `atlasRotate180` | bool | true | random 180° draaien toestaan |

### Weergave
| Parameter | Type | Default |
|---|---|---|
| `previewMode` | bool | false | eenvoudige blokjes zonder chamfer, voor snelle viewport |

---

## 7. Verbanden (bonds)

Verbanden worden als **data** gedefinieerd, niet hardcoded in de mesh-code. Een verband is een herhalende reeks lagen; elke laag is een lijst eenheden met een start-offset.

Implementatie: offset = `aL·L + aB·B + aJ·stootvoeg` met coëfficiënten `[aL, aB, aJ]` per laag; eenheden `#S` (strek), `#K` (kop), `#KM` (kop op halve strekmodule). Zie `BrickGen_Bonds.ms`.

```
-- pseudocode
bond = (
  name: "vlaams",
  courses: #(
    (offset: 0,                units: #(#S, #K)),   -- strek, kop, strek, kop...
    (offset: (L+B+2*hj)/2 ...)  -- zodat koppen centraal op strekken liggen
  )
)
```

Eerste set (fase 1):
1. **Halfsteens** (stretcher bond): enkel strekken, elke laag ½ steen verschoven.
2. **Staand / stapelverband** (stack bond): enkel strekken, geen verschuiving.
3. **Vlaams verband**: elke laag strek–kop afwisselend; koppen centraal op de strek eronder.
4. **Kruisverband**: lagen afwisselend volledig strekken en volledig koppen; elke tweede strekkenlaag ½ steen verschoven. Koppen staan op een halve strekmodule ((L + stootvoeg)/2), zodat ze niet uit de lijn lopen als 2·(B + voeg) ≠ L + voeg (bv. 2·112 ≠ 222). De stootvoeg in de koppenlaag past zich dus aan, zoals bij echt metselwerk.
5. **Wild verband**: halfsteens maar met random offset per laag (min. overlap ¼ steen, configureerbaar) en regels tegen te veel stootvoegen boven elkaar ("trapjes"/"vertandingen" vermijden).

Uitbreidbaar later: Engels verband, Noors, ¼-steens, dokken, ... Een nieuw verband toevoegen mag **enkel** een nieuwe definitie in `BrickGen_Bonds.ms` vereisen.

Aan de randen van de muur worden stenen **afgezaagd** op `wallLength`. Afgezaagde stenen krijgen correct ingekorte UV's (zie §9).

---

## 8. Geometrie per steen

Doel: zo weinig mogelijk polygonen, enkel zichtbare zijdes.

Per steen (normale modus):
- **Voorvlak**: 1 quad, ingezet met de chamfer.
- **Chamferring**: 4 quads van de rand van het voorvlak naar de buitenrand.
- **Zijkanten**: 4 quads van de buitenrand naar diepte `jointRecess + chamfer + 3 mm` (net genoeg om onder de voeg te verdwijnen).
- **Geen** achterkant.

→ 9 quads = **18 tris per steen**. Een gevel van 200 m² (~14.000 stenen) ≈ 250.000 tris. Ruim binnen budget.

Imperfecties (in deze volgorde toepassen):
1. `sizeJitter` op L en H.
2. `chamfer` × (1 ± `chamferJitter`).
3. `cornerJitter`: random offset in X/Z op de 8 voorste hoekpunten (voorvlak + buitenrand), Y licht mee.
4. `depthJitter`: hele steen verschuiven in Y.
5. `rotJitter`: rotatie rond Y-as door het steenmiddelpunt.

Smoothing: voorvlak eigen smoothing group, chamfer + zijkanten een andere, zodat de chamfer de randen zacht laat ogen zonder het voorvlak te vervormen.

Elke steen is een **apart mesh-element** (geen gedeelde vertices met buren). Dat maakt "random by element" in V-Ray mogelijk.

### Voeg
- Eén vlak (of één vlak per laag als dat UV-gewijs handiger is) op `y = jointRecess`, over de hele muur.
- Material ID = `mortarMatId`.
- UV: planair op wereldmaat (zie kanaal 2).

### Performance-regels voor MAXScript
- Bouw vertices, faces, material ID's en UV's eerst in **arrays**, en zet de mesh in één keer (`setMesh` met vertex- en face-arrays, daarna `setNumTVerts`/`buildTVFaces` en per face `setTVFace`). Nooit per steen een node aanmaken of `attach` in een lus.
- Gebruik `with redraw off` en `undo off` tijdens het bouwen waar zinvol.
- Doel: een muur van 3 × 2,5 m bouwt onder 0,2 s; een gevel van 200 m² onder 3 s. Meten en loggen in fase 1.
- Als het object te traag reageert bij interactieve parameterwijziging: `previewMode` of een "Rebuild"-knop in plaats van live rebuild bij elke spinner-stap.

---

## 9. UV-kanalen en atlas

| Kanaal | Inhoud |
|---|---|
| **1** | Atlas-UV: voorvlak en chamfer van elke steen gemapt naar een willekeurige cel van de bronstextuur. |
| **2** | Muur-planaire UV in echte maat (1 UV-eenheid = 1 m). Voor vuil, verkleuring, grunge en de voeg. |
| **3** (optioneel) | Per steen één constante random waarde in U (0–1). Bruikbaar voor tint-variatie via map-kanaal-gestuurde maps. |

### Atlas-mapping per steen
1. Kies een cel uit de atlas met de steen-RNG. Cellen met `"disabled": true` overslaan. Kop-stenen gebruiken bij voorkeur cellen met `"kind": "header"` als die bestaan, anders een uitsnede van een strek-cel.
2. Map het **voorvlak** op de cel-rechthoek (in genormaliseerde UV).
3. Map de **chamferring** op een rand van ~`chamfer`-breedte rond de cel, zodat de chamfer de rand van de steen in de foto toont.
4. Zijkanten: op de buitenste pixels van de cel (uitgerekt). Die zijn nauwelijks zichtbaar.
5. Random spiegelen (U en/of V) en 180° draaien als toegelaten.
6. **Afgezaagde steen**: neem een deel van de cel in verhouding tot de werkelijke lengte (van links of rechts, random).
7. Als de cel-verhouding niet overeenkomt met de steenverhouding: centraal uitsnijden (crop), niet uitrekken.

Zonder atlas-bestand: kanaal 1 krijgt een per-steen 0–1-mapping over de volledige (niet-afgezaagde) steen; afgezaagde stenen krijgen een deel ervan. Voor een gewone tegelende baksteentextuur gebruik je kanaal 2 (echte maat). In fase 2 wordt het 0–1-vierkant van kanaal 1 naar de atlascel getransformeerd.

### Atlas-JSON (formaat)

```json
{
  "version": 1,
  "name": "Handvorm rood 01",
  "image": { "width": 4096, "height": 4096 },
  "maps": {
    "diffuse": "handvorm_rood_01_diffuse.jpg",
    "normal": "handvorm_rood_01_normal.png",
    "roughness": "handvorm_rood_01_rough.jpg",
    "bump": null
  },
  "realBrick": { "L": 210, "H": 50 },
  "cells": [
    { "id": 0, "x": 12, "y": 8, "w": 402, "h": 96, "kind": "stretcher", "disabled": false },
    { "id": 1, "x": 430, "y": 8, "w": 398, "h": 95, "kind": "stretcher", "disabled": true }
  ]
}
```

- Pixelcoördinaten met de oorsprong **linksboven** (zoals in de webtool). Bij het omzetten naar UV: `v = 1 − (y / height)`.
- Bestandspaden in `maps` zijn relatief ten opzichte van het JSON-bestand.

---

## 10. Materiaal (V-Ray)

Knop **"Maak materiaal"** in de plugin-UI bouwt automatisch:
- `VRayMtl` voor de stenen:
  - Diffuse: bitmap van de atlas (kanaal 1), via `VRayMultiSubTex` of `VRayColorCorrection` met lichte random tint per element (mode "random by element").
  - Normal: `VRayNormalMap` met de atlas-normal (kanaal 1).
  - Roughness/reflectie: atlas-roughness (kanaal 1).
- Aparte `VRayMtl` voor de voeg (kanaal 2, eenvoudige mortel-textuur of effen kleur met noise).
- Alles in een `Multimaterial` met ID 1..N voor de stenen en `mortarMatId` voor de voeg.

Bedoeling: een collega klikt op "Maak materiaal" en heeft meteen een renderbare gevel zonder handwerk.

---

## 11. Webtool: atlas-editor (GitHub Pages)

Puur client-side: HTML + JS + canvas, geen frameworks nodig (eventueel een kleine library voor zoom/pan).

### Functies
1. Diffuse-textuur inladen (slepen of bestand kiezen). Eventueel normal- en roughness-maps koppelen; die gebruiken dezelfde cellen.
2. **Automatisch raster voorstellen**: geef het aantal lagen en stenen per laag op. Optioneel automatische detectie van de voeglijnen via helderheidsprofielen (gemiddelde helderheid per rij en per kolom → minima = voegen).
3. **Handmatig bijstellen**:
   - horizontale lijnen per laag verslepen;
   - verticale lijnen **per laag** verslepen (lagen zijn verschoven en foto's zijn nooit perfect recht);
   - per cel de randen fijn afstellen.
4. Cellen **uitschakelen** met een klik (afgesneden, logo, vlek, te donker).
5. Cel markeren als `stretcher` of `header`.
6. Echte steenmaat invullen (L×H in mm).
7. **Exporteren** naar het atlas-JSON-formaat (§9).
8. Optioneel: losse cellen exporteren als PNG (zip). Niet nodig voor de plugin, wel handig voor ander gebruik.
9. Een bestaand JSON-bestand terug inladen om te bewerken.

### Tips voor goede bronnen
- Vlak belichte texturen zonder sterke schaduwen of gradiënt.
- Hoge resolutie: bij 20 stenen in de breedte op 4K heb je ongeveer 200 px per steen.
- Seamless texturen van baksteenfabrikanten (bv. Vandersanden, Wienerberger) zijn vaak goede bronnen. Let op de licentie (zie §15).

---

## 12. Fasering met acceptatiecriteria

### Fase 0 — Opzet (½ dag)
- [x] Private GitHub-repo aangemaakt met de structuur uit §3. (Verhuis naar de organisatie: zie README of de chat.)
- [x] `CLAUDE.md` met verwijzing naar dit plan.
- [x] Minimale versie van 3ds Max en V-Ray vastgelegd in `README.md` (voorstel: Max 2022+, V-Ray 6+; te bevestigen, §16).
- [ ] Testscène `testscenes/test_gevel.max`: camera, licht, een vlak waar de muur komt. Script staat klaar (`BrickGen_MakeTestScene.ms`); het .max-bestand moet nog in 3ds Max aangemaakt en gecommit worden.

### Fase 1 — MVP rechte muur (1–2 weken)
> Status (3ds Max 2026): alle functionele tests slagen. Eerste meting: 7,5 m² in 305 ms, 200 m² in 8,3 s (doel 0,2 s / 3 s). Optimalisatieronde 1 loopt (minder RNG-aanroepen, autoEdge, timing per fase).

- [ ] Scripted plugin `BrickWall` verschijnt in Create-panel en is te tekenen met muis (lengte, dan hoogte).
- [ ] Parameters uit §6 (Muur, Steen, Voeg, Verband, Vorm/imperfectie, matIdCount, mortarMatId) werken.
- [ ] Verbanden: halfsteens, staand, Vlaams, kruis, wild.
- [ ] Stenen volgens §8: 18 tris, enkel zichtbare zijdes, elk een apart element.
- [ ] Afgezaagde stenen aan linker- en rechterrand; bovenste laag afgezaagd op `wallHeight`.
- [ ] Voegvlak op `jointRecess`.
- [ ] Random material ID per steen (1..N), voeg op `mortarMatId`.
- [ ] Zelfde seed = identieke muur (testen door twee keer te bouwen en vertices te vergelijken).
- [ ] UV-kanaal 2 (planair, echte maat).
- [ ] Bouwtijd gemeten en gelogd voor 7,5 m² en 200 m².

### Fase 2 — Atlas-texturering (1 week)
> Status: gecodeerd, te testen in 3ds Max. `BrickGen_Atlas.ms` (JSON-atlas, cache, cel per steen via RNG-kanaal 3, centrale crop, spiegelen/draaien, kop/strek), `BrickGen_Material.ms` ("Maak materiaal", V-Ray of Physical). Getest: werkt (voegkleur, glans en relief instelbaar sinds de test, live op het materiaal). Eerste atlas: `presets/atlases/baksteen_rood_01.json` (Vlaams verband, Waalformaat, 340 cellen) automatisch gedetecteerd met `tools/detect_atlas.py` — referentie-algoritme voor de webtool. De textuur zelf staat in de (private) repo voor intern gebruik; niet meeleveren bij verkoop (§15).

- [ ] Atlas-JSON inlezen (`BrickGen_Atlas.ms`). Eenvoudige JSON-parser in MAXScript of via `dotNet` (`System.Web.Script.Serialization` of Newtonsoft als beschikbaar).
- [ ] UV-kanaal 1 volgens §9, inclusief spiegelen, draaien, afgezaagde stenen en kop/strek-keuze.
- [ ] Fallback zonder atlas.
- [ ] Knop "Maak materiaal" volgens §10.
- [ ] Test: render van de testgevel toont geen zichtbare herhaling.

### Fase 3 — Textuur kiezen zonder JSON (vervangt de webtool als eerste stap)
> Beslissing (na fase 2-test): gebruikers kiezen gewoon een **jpg/png**; geen JSON, geen aparte webtool nodig voor het gewone geval.
> - **Kies textuur...** in de modifier aanvaardt jpg/png/tif. BrickGen detecteert de stenen automatisch in 3ds Max (algoritme van `tools/detect_atlas.py`, in C# dat 3ds Max zelf compileert via `dotNet`, dus geen Python nodig; doel < 2 s voor een foto van 2000 px).
> - Het resultaat wordt als cache naast de foto bewaard (`foto.brickgen.json`), onzichtbaar voor de gebruiker; volgende keer meteen geladen. Bestaande JSON-atlassen blijven werken.
> - Een **controlevenster** in Max toont de foto met de gevonden stenen (kader per cel, kop/strek in een andere kleur); klik om een cel uit/aan te zetten, en sliders voor steenformaat/voegbreedte als de detectie ernaast zit.
> - Het materiaal blijft gekoppeld aan de modifier ("Maak materiaal" + live voegkleur/glans): de UV's hangen af van de cellen, dus de foto hoort bij de geometrie. Een Material Editor-variant (eigen texmap "BrickGen textuur") is mogelijk maar bewust later: dan moet de modifier de foto uit het materiaal lezen en dat is foutgevoeliger (materiaal vervangen of in een Multi/Sub nesten breekt de koppeling).
> - Normal/roughness: optioneel extra foto's met dezelfde afmetingen, automatisch herkend op naam (`_normal`, `_rough`).

> Status: `BrickGen_Detect.ms` gecodeerd in pure MAXScript in plaats van C# (runtime-compilatie van C# is onzeker sinds 3ds Max op .NET 8 draait). Werkt op een verkleinde kopie (max 900 px): in een Python-simulatie van exact dit algoritme 327 van de 340 cellen op `baksteen_rood_01.jpg`. Extra t.o.v. de referentie: valse lintvoegen (donkere vlekken) worden weggefilterd. Displacement-optie geschrapt na test (bump volstaat).

- [x] Detectie in 3ds Max (`BrickGen_Detect.ms`), getest op de bestaande foto: 360 cellen in 3,2 s, werkt met Vlaams en halfsteens.
- [x] "Kies textuur..." voor jpg/png + cache naast de foto (of in %TEMP%\BrickGen als die map niet schrijfbaar is).
- [ ] Controlevenster met overlay en cellen aan/uit.
- [ ] Herkennen van normal/roughness-maps op naam.

### Fase 3b — Webtool (optioneel, later)
- [ ] Alle functies 1–7 uit §11.
- [ ] Export valideert tegen het JSON-formaat.
- [ ] Gepubliceerd op GitHub Pages (kan ook vanuit een private repo bij een betaald GitHub-plan; anders de webtool in een aparte publieke repo zetten of lokaal openen).

### Fase 4 — Openingen en hoeken (2–3 weken, moeilijkste fase)
- [ ] Openingen via **picken van box-objecten** (of gesloten splines) in de UI.
- [ ] Stenen volledig binnen een opening: verwijderd. Stenen deels erin: afgezaagd, met correcte UV's.
- [ ] Muur volgens een **spline** (rechte segmenten), meerdere muurdelen in één object.
- [ ] Hoeken van 90°: verband loopt correct rond de hoek met koppen en klezoren waar het verband dat vereist. Zichtbaar steenvlak aan beide zijden van de hoek (hoeksteen toont kop of strek op de andere zijde).
- [ ] Andere hoeken dan 90°: voorlopig afgezaagd met verstek, zonder verbandcorrectie.

### Fase 5 — Details (doorlopend)
- [ ] Rollagen boven openingen (staand of op kant).
- [ ] Raamdorpels/lateien als aparte eenvoudige geometrie of overslaan van stenen.
- [ ] Uitspringende/terugliggende lagen (siermetselwerk).
- [ ] Afgebrokkelde stenen: een paar vooraf gedefinieerde "schade-varianten" van de chamferring, toegepast op `damagedPct` van de stenen.
- [ ] Voegvariaties: platvol, terugliggend, gesneden (licht schuin).

### Fase 6 — Performance en workflow
- [ ] `previewMode`.
- [ ] Knop "Bake naar V-Ray proxy" (`vrayMeshExport`).
- [ ] Knop "Convert to Editable Poly" (bevriezen).
- [ ] Gevel van 300 m² of meer zonder merkbare traagheid in viewport na het bouwen.

### Fase 7 — Intern uitrollen
- [ ] `.mzp`-installer of instructie voor een gedeelde scriptmap op het netwerk.
- [ ] Presetbibliotheek op gedeelde schijf (formaten + atlassen + materiaal-instellingen).
- [ ] `README.md` met installatie en korte gebruiksgids met screenshots.
- [ ] Twee à drie echte projecten door collega's laten testen; feedback in GitHub Issues.

### Fase 8 — Eventueel verkopen
- [ ] Licentiecontrole (Lemon Squeezy/Gumroad license-key API).
- [ ] Besluit over bescherming: `encryptScript` is zwak; bij succes de kern overwegen in C++ (3ds Max SDK).
- [ ] Website, demovideo, documentatie.
- [ ] Geen texturen van derden meeleveren (zie §15); eventueel eigen gefotografeerde demo-atlassen.
- [ ] Eventueel Supabase of iets vergelijkbaars voor een online atlas-/presetbibliotheek.

---

## 13. Testen

- **Determinisme**: zelfde parameters + seed → identieke vertex-posities.
- **Randen**: muurlengtes die geen veelvoud van de steenmaat zijn; zeer korte muren (< 1 steen); zeer hoge muren.
- **Extreme parameters**: voeg 0 mm, chamfer 0, chamfer groter dan de halve steenhoogte (moet geklemd worden).
- **Eenheden**: testscène in mm, cm en m — de muur moet overal dezelfde echte maat hebben.
- **Performance**: bouwtijd loggen bij elke grote wijziging (eenvoudige timing met `timeStamp()`).
- **Render**: vaste camera in testscène; na elke fase een vergelijkingsrender in `docs/screenshots/`.

---

## 14. Werkafspraken voor Claude Code

- Werk **fase per fase**; begin pas aan een volgende fase als de acceptatiecriteria van de huidige afgevinkt zijn.
- Code en identifiers in het **Engels**, UI-labels mogen Nederlands zijn (later meertalig).
- Kleine, duidelijke commits per afgewerkt onderdeel.
- MAXScript kan niet in de container getest worden: lever code die rechtstreeks in 3ds Max geëvalueerd kan worden, met duidelijke instructies hoe te testen, en vraag om feedback/foutmeldingen uit de MAXScript Listener.
- Geen nieuwe externe afhankelijkheden zonder overleg.
- Werk dit document bij wanneer een beslissing verandert.
- `BrickWall`: `classID` en de volgorde van parameters en verbanden nooit wijzigen (opgeslagen scènes hangen ervan af); enkel achteraan toevoegen.

---

## 15. Juridische aandachtspunten (geen juridisch advies)

1. **Eigendom van de code**: als dit gebouwd wordt voor of binnen het bureau (zeker tijdens betaalde uren), vooraf schriftelijk vastleggen wie de rechten heeft en hoe die verdeeld worden bij een eventuele verkoop. Laat dit eventueel nakijken.
2. **Texturen**: texturen van fabrikanten of betaalde bibliotheken mogen meestal intern gebruikt worden, maar niet meegeleverd worden in een verkocht product. De plugin laat gebruikers hun eigen texturen inladen.
3. **Namen**: controleer bij verkoop of de productnaam niet al gebruikt wordt.

---

## 16. Open vragen

- Minimale 3ds Max- en V-Ray-versie? (Voorstel: Max 2022+, V-Ray 6+. De code vraagt technisch minstens Max 2017.1.)
- Live rebuild bij elke parameterwijziging, of een "Rebuild"-knop bij grote muren? (Nu: live rebuild; beslissen na de timing-resultaten van fase 1.)
- Hoeken: enkel buitenhoeken of ook binnenhoeken in fase 4?
- Moet de muur ook een binnenblad/spouw tonen bij openingen (zichtbare dagkant)?
- Productnaam?
- ~~Modifier i.p.v. object?~~ **Beslist:** BrickGen wordt vooral als **modifier op een spline** gebruikt (workflow: spline → BrickGen, in plaats van spline → Extrude). Haalbaarheid bevestigd in 3ds Max 2026 met `testscenes/BrickGen_ProbeModifier.ms` (`simpleMeshMod` leest de spline onder zich). De spline is de **omtrek van één gevelvlak**, getekend in een gevelaanzicht (Front/Left/Right/Back) over het gevelplan; BrickGen vult dat vlak, extra gesloten splines zijn openingen (ramen, deuren). Eerste versie in `BrickGen_Modifier.ms` + `BrickGen_Region.ms`: per laag worden de stenen afgezaagd op de binnen-intervallen (even-odd), exact voor horizontale/verticale randen, schuine randen per laag verticaal. Daarmee is ook "openingen" uit fase 4 grotendeels gedekt. Dagkanten: parameter `revealDepth` (gevraagd: de dikte van de gevel, bv. 40 cm, moet in de openingen zichtbaar zijn met doorlopende bakstenen); per horizontale/verticale rand een strook stenen op het laagraster van de gevel (`buildRevealsInto`). Hoeken bij openingen: een automatische hoekoplossing (hoeksteen per laag, verband uitzetten vanaf de hoek, hoekregel per verband) is geprobeerd en **weer verwijderd**: ze bleef niet kloppen voor alle verbanden en gaf rare passtenen in penanten. **Beslist (gebruiker):** de gevel volgt het globale patroon (startoffset) en de dagkanten krijgen een instelbare **Dagkant offset** (`revealOffset`, gemeten vanaf de gevelvoorkant de muur in) waarmee de gebruiker zelf het verband in de dagkant laat aansluiten. Eenvoudig en voorspelbaar. Rollagen blijven fase 5. **Getest in 3ds Max 2026** (gevel 7 × 4 m met raam en deur, dagkant 40 cm): ±2.900 stenen / 54k tris, 0,5–1 s per wijziging; cache voorkomt herberekening bij navigeren. Het `BrickWall`-object blijft bestaan voor losse testmuren.
