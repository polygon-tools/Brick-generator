# CLAUDE.md

**Lees [PLAN.md](PLAN.md) volledig voor je code schrijft.** Dat document is de bron van waarheid. Werk fase per fase (§12) en volg de werkafspraken in §14.

Kort:
- MAXScript kan niet in de container draaien. Lever code die rechtstreeks in 3ds Max geëvalueerd kan worden, met testinstructies, en vraag om de Listener-output.
- Code en identifiers in het Engels, UI-labels in het Nederlands.
- Intern rekenen in mm; omzetten naar systeemeenheden met `units.decodeValue "1mm"`.
- Randomness enkel via `BrickGenRNG` (seed, steenindex, kanaal). Nooit de globale `random` voor geometrie. Een nieuwe random-parameter = een nieuw kanaalnummer; bestaande kanalen nooit hergebruiken.
- `BrickWall`: `classID` nooit wijzigen. Parameters nooit verwijderen of herschikken, enkel achteraan toevoegen (scènes slaan ze op). Zo ook voor de volgorde van de verbanden in `BrickGen_Bonds.ms` (de index wordt opgeslagen).
- Laadvolgorde staat in `maxscript/BrickGen_Startup.ms`. Een nieuw bestand moet daar ook bij.
- Kleine commits per afgewerkt onderdeel. Werk PLAN.md bij als een beslissing verandert.
- MAXScript-valkuilen (getest in 3ds Max 2026):
  - In een struct kan een functie enkel functies aanroepen die **eerder** in de struct staan (anders: "Call needs function or class, got: undefined").
  - In een top-level blok `( ... )` worden globals die pas tijdens dat blok via `fileIn` ontstaan als lokaal gezien: gebruik `::Naam`.
  - Een nieuwe TriMesh heeft enkel map channel 0 en 1: `meshop.setNumMaps` vóór kanaal 2+.
  - `pi` is een constante: niet als variabelenaam gebruiken.
