# Platform Docking (Factorio 2.0 / Space Age mod)

## Research rules
- Before writing or changing any code that uses the Factorio Lua API or
  prototypes, look it up with the `factorio-ai-tools` MCP server. Don't rely
  on memory for API names, signatures, or behavior.
- Always use version `2.0.76` for `search_factorio_docs` and
  `search_factorio_prototypes`.
- For edge cases and known pitfalls, also check `search_factorio_forums`.
- If the docs and the forums disagree, say so and prefer the docs.
- Cite which API classes or methods you looked up when explaining a change.

## Project notes
- Entry point: control.lua (event wiring only). Core logic: scripts/merger.lua
  (dock/undock via LuaSurface.clone_brush), scripts/footprint.lua (tile sets),
  scripts/logistics.lua (request-based hub transfer), scripts/gui.lua.
- The larger platform hosts; the guest's layout is cloned onto the host's
  surface. The guest platform stays hidden + paused and follows the host's
  space_location, so docked platforms fly together.
- Never push to main: .github/workflows/release.yml publishes to the mod portal.
- Carrier docking: a host can hold several guests (Carrier Clamps tech);
  platform lookups scan storage.docked_pairs (State.pair_ids_of). Guests can
  launch in flight (Merger.launch → execute_unmerge{launch=true}).
- scripts/lane.lua reverts floor built in front of docking ports.
- Roadmap: docs/ROADMAP.md. Known unfinished: real art. In-game checks still
  needed: writing distance/speed on a launched guest, tile_buildability_rules
  rotating with the port.