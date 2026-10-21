# 500 × 500 m Extraction Map — Detailed Level Design Pack

This pack expands the user-supplied `map_500m_zoning_sketch.svg` into a **proposed** buildable blockout. The original source established zones, major road, access tracks, rail, water, 2 spawn sites, and 4 extraction sites. Buildings, cover, optional crossings, and loot descriptions in this pack are design additions.

## Files

- `detailed_master_map.svg` — editable annotated full-map plan; `.png` is quick preview.
- `zone_{town,industry,bunker,hills,forest,farmland,river,lake}.svg` — zoom-in plans for each zone; PNG copies for viewing.
- `map_layout_godot.json` — structured coordinates, building footprints, heights, tree instances, cover clusters, POI tags, route lines, and spawn/extract positions.
- `godot_agent_implementation_prompt.md` — ready-to-use instructions for Codex/Claude coding agent.

## Coordinate convention

Godot 4.x: map center is `(0,0,0)`, +X east, **−Z north**, +Y upward. Terrain spans X/Z from −250 to +250 meters. SVG map square spans pixels 30–470, with `X=(svg_x-250)*500/440`, `Z=(svg_y-250)*500/440`.

## Priority

1. Import map JSON and render 500m ground/8 color zones, flat.
2. Set roads, bridge, railroad, river/lake collision and navigable paths.
3. Place modular building proxies, trees and cover.
4. Connect entrances and bake navigation in chunks.
5. Hook up S1/S2, E-A/E-B/E-C/E-D and simple gameplay checks.
6. Add elevation, props, modular interiors and visual pass last.

## Special design precautions

- R01 central road bridge must pass travel tests: the entire road should remain connected east-west.
- R02 and R03 are *proposed* alternate river crossings, not present in the original sketch.
- E-B and E-C are physically close: balance their extraction conditions so they do not feel redundant.
- E-D is west-side, like both starting spawns. Consider giving it a distinct conditional-extraction requirement.
- The bunker underground interior is intentionally only a scene portal stub until separately designed.
- Object boxes are first-pass floor plans; use blue/orange validation overlays or nav debug to correct overlaps and height profiles.
- Trees are deterministic (explicit coordinates). Use instancing rather than spawning a scene script for each tree.

## Coordinate constraints

Footprints are center positions + dimensions in meters; positive rotation rotates around up axis. Structures are mostly axis-aligned. `position_xz_m` values are derived from the source 500m sketch; `floors`, loot, and gameplay notes are design proposals.
