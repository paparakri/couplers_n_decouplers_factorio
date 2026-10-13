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
- Known unfinished parts: placement restriction / build exclusion zone for the
  port, real art (Step 5). In-game checks still needed: clone_brush offset
  semantics, writing space_location on the hidden guest.