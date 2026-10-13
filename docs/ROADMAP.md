# Super Space Age — Road to Release

> **Pitch:** Space Age gives you ships. **Super Space Age** gives you a *space program*: ships that dock, carry and launch each other, a solar system with weather and radiation you have to plan around, derelicts worth salvaging, and asteroids worth anchoring to.

This is the full plan from today's working docking prototype to a polished 1.0 on the Mod Portal: features, mechanics, art, audio, balance, testing and the launch kit.

---

## Contents

1. [Vision](#1-vision)
2. [Landscape: what already exists](#2-landscape-what-already-exists)
3. [Mod structure & name](#3-mod-structure--name)
4. [Where we are today](#4-where-we-are-today)
5. [Module A — Docking](#5-module-a--docking)
6. [Module B — Space Weather & Radiation](#6-module-b--space-weather--radiation)
7. [Module C — Asteroid Anchoring & Mining](#7-module-c--asteroid-anchoring--mining)
8. [Module D — Derelicts](#8-module-d--derelicts)
9. [Gameplay loops](#9-gameplay-loops)
10. [Technology & progression](#10-technology--progression)
11. [Art, audio & presentation](#11-art-audio--presentation)
12. [Engineering work](#12-engineering-work)
13. [Testing](#13-testing)
14. [Mod Portal & launch kit](#14-mod-portal--launch-kit)
15. [Milestones](#15-milestones)
16. [Open decisions](#16-open-decisions)
17. [Parked ideas](#17-parked-ideas)

---

## 1. Vision

In vanilla Space Age every platform has to be fully self-sufficient, and space itself is mostly a backdrop: asteroids on the route, and that's it. Late-game destinations are solved by building one enormous ship.

Super Space Age changes two things:

1. **Ships cooperate.** A big ship can carry small ones, launch them mid-flight and collect them again. A parked depot can refuel visitors. A cheap shuttle can reach a hostile planet because it only needs enough fuel to get back to the tanker in orbit.
2. **Space has conditions.** Meteor showers and solar flares come and go on a forecast you can read. Orbits close to the sun are radioactive. Derelicts drift into orbit. Big asteroids can be anchored to and mined.

Design pillars:

| Pillar | In practice |
|---|---|
| **Never lose the player's stuff** | Every operation that moves entities checks first and verifies after; on any mismatch nothing is removed. |
| **Plannable, not random** | Hazards are forecast in advance and readable by circuits, so players solve them with automation, not luck. |
| **Feels mechanical** | Clamps close, bridges extend, tethers lock. Every event looks and sounds like one. |
| **Automatable** | Anything a player can click, a circuit network can do. |
| **Vanilla-friendly** | Real vanilla entities and tiles; no hidden inventories or fake surfaces. Each module can be switched off. |

---

## 2. Landscape: what already exists

Checked on the Mod Portal before planning. Nothing here should be a me-too feature.

| Mod | What it does | How we differ |
|---|---|---|
| [TFMG Platform Docking](https://mods.factorio.com/mod/TFMG-platform-docking) (~4.7k downloads, 2.1) | Two **parked** platforms connect through docking belts/pipes; circuit-controlled docking with a shared signal. Disconnects when either platform moves. Self-described as "pretty barebones". | We **merge** platforms into one surface that **flies together**, carry several guests, and launch them mid-flight. Couplers and circuit docking are supporting features, not the headline. |
| [Ship Age](https://mods.factorio.com/mod/Shipage) (alpha, 2.1) | Ships built on stations fly between persistent stations and dock to them. | Ship Age replaces vanilla platforms with its own ship/station model. We keep vanilla platforms and make *them* modular. |
| [Interplatform Requests](https://mods.factorio.com/mod/interplatform-requests), [Orbital Transfer](https://mods.factorio.com/mod/orbital-transfer) | Item transfer between platforms at the same location. | Not competing. Our hub transfer is a small bonus while docked. |
| [Space battles](https://mods.factorio.com/mod/space-battles), [Fall of Promethea](https://mods.factorio.com/mod/fall-of-promethea-2) | Enemy ships attack platforms. | Out of scope; we don't add combat. |
| [Space Expeditions](https://mods.factorio.com/mod/Space-Expeditions) (deprecated) | Expeditions to debris fields and wreckage. | Abandoned; our derelicts are built on docking and run in orbit. |
| Space weather / radiation | No current mod found. | Open space. |
| Asteroid anchoring / mining | No current mod found. | Open space. |

**How to explain the difference in one line:** *Other mods connect platforms or let ships fly between stations. Super Space Age turns platforms into a fleet — they dock, merge, fly as one, launch each other — and gives that fleet a solar system worth planning around.*

---

## 3. Mod structure & name

**Name:** *Super Space Age*. Internal name `super-space-age` (checked: not taken on the Mod Portal). The internal name is permanent once published.

**Structure:** one mod, four modules, each with a **startup setting** to turn it off:

| Module | Startup setting | Default |
|---|---|---|
| A — Docking | always on (core) | — |
| B — Space Weather & Radiation | `ssa-enable-weather`, `ssa-enable-radiation` | on |
| C — Asteroid Anchoring & Mining | `ssa-enable-asteroid-mining` | on |
| D — Derelicts | `ssa-enable-derelicts` | on |

Why one mod rather than four: one page to grow downloads and reviews, one version to keep compatible, shared code (docking is reused by modules C and D). Toggles keep it friendly for players who only want some of it.

**Code layout** (target):

```
scripts/
  core/        state, footprint, util, events (shared)
  docking/     merger, corridor, couplers, carrier, launch, gui
  weather/     forecast, meteor, flare, radiation, shields
  asteroids/   spawner, anchor, mining
  derelicts/   beacon, generator, salvage
```

---

## 4. Where we are today

**Working (0.1.0, tested in-game, Factorio 2.0):**

- Docking Port entity, recipe and technology (placeholder art).
- Dock two platforms: the larger hosts; the guest is copied onto the host's surface with `clone_brush`.
- Bridge between ports, with length and width chosen per dock.
- Fit check before docking; entity-count verification on dock and undock; rollback on mismatch.
- Docked platforms fly together; the guest follows the host's location.
- Undock (including queued undock while in transit); boundary entities mined into the host's hub.
- Automatic undock when a port is destroyed or a platform deleted.
- Hub-to-hub transfer that fills logistic requests.
- Players' views follow the guest on dock and undock.

**Known gaps:** placeholder art, no placement restriction, one guest per host, no circuit support, no automated tests, multiplayer and big-save performance untested, **still on Factorio 2.0** (see 12.1).

---

## 5. Module A — Docking

Priorities: **Must** (1.0), **Should** (1.0 if time allows), **Could** (post-1.0).

### 5.1 Core docking polish — *Must*

- **Placement rule:** ports only on the platform edge, docking face over empty space (`tile_buildability_rules`).
- **Exclusion zone:** nothing may be built in front of a port; shown as a striped area while placing.
- **Docking preview:** ghost outline of where the guest and bridge will land, red where it overlaps (`LuaRendering`).
- **Combined stats panel:** combined weight, thrust and estimated speed. The 2.0 acceleration formula takes platform **width and height** as inputs (`UtilityConstants.space_platform_acceleration_expression`), so side-by-side docking may cost speed. Showing it makes port placement a real design choice.

### 5.2 Carrier docking (multiple guests) — *Must*

One host, many guests, one port per guest. Each guest has its own pair, bridge and footprint, and undocks independently. No chains (a guest can't host). Storage changes from "platform → pair" to "host → list of pairs, guest → pair".

### 5.3 In-flight launch & recovery — *Must* (headline feature)

A docked guest can **launch while the host is travelling**. The guest appears on the same route, near the host's position, and continues with its own schedule. Later it docks again at any stop.

- **How:** `LuaSpacePlatform.space_connection` is writable ("sets the distance to 0.5"). After undocking the guest's content back onto its own surface, set the guest's connection to the host's, then set `distance` to the host's.
- **Spike needed:** confirm `distance` is writable after setting the connection. If it isn't, the guest launches from the route midpoint, which is still usable.
- **Uses:** carriers releasing harvesters on the way to the shattered planet; emergency jettison of a damaged module; scouts that split off to a second planet.
- **Recovery:** a guest can only re-dock when both are stopped at the same location (in-flight rendezvous stays parked, see section 17).

### 5.4 Couplers — *Must*

Entities that link logistics across the bridge automatically on dock and unlink on undock. (The original repo name, *couplers & decouplers*, comes from these.)

| Coupler | While docked | How |
|---|---|---|
| **Belt coupler** | Belt in one coupler comes out of its partner. | Vanilla `linked-belt` type, linked on dock. |
| **Fluid coupler** | Fluid flows between partners at a fixed rate. | Script moves fluid between fluid boxes. Rate scales with quality. |
| **Power coupler** *(Should)* | Shares electricity. | Script-connected poles. |

Couplers pair by **channel**. Nothing straddles the boundary, so undocking never has to mine anything.

### 5.5 Automated docking (circuits) — *Must*

**Inputs** on the port: `D` = dock with a compatible port sharing the same **docking code**; `U` = undock; `L`/`W` = bridge size; `J` = launch now (in-flight launch).
**Outputs:** `D` docked, `C` connecting, `F` partner present and fits.
With platform schedules this makes fully automated tanker and carrier loops possible.

### 5.6 Depot mode — *Should*

A port setting that turns a platform into a service station: accepts any dock with its code, auto-releases guests on a circuit condition, and only pushes items/fluids to guests, never pulls.

### 5.7 Hub logistics upgrades — *Should*

Transfer history in the docked view; per-pair direction toggle; respect the hub's "trash unrequested" setting.

### 5.8 Feedback & feel — *Must*

Clamp and bridge-extend animation during the countdown, reverse on undock, sounds, custom alerts, alt-mode partner labels.

---

## 6. Module B — Space Weather & Radiation

Space stops being a static backdrop. Every hazard is **forecast**, so players respond with planning and automation.

### 6.1 Forecast — *Must*

- Each space route and location has a repeating **weather cycle**: calm → warning → event → calm. Timings are seeded per save so they're predictable once learned.
- The hub outputs forecast signals: ticks until the next event and its type, per destination. Platform schedules can then *wait for a calm window* before departing.
- A **forecast panel** (GUI) shows the upcoming events on each route, like a train timetable for space.

### 6.2 Meteor showers — *Must*

- During a shower on a route, extra asteroids hit platforms travelling it: a short, heavy wave on top of vanilla asteroids.
- **How:** spawn asteroid entities with `LuaSurface.create_entity` near the platform's leading edge.
- **Spike needed:** check that script-created asteroids move and behave like naturally spawned ones (vanilla spawning runs in the engine; only the global `AsteroidMapSettings.spawning_rate` is exposed). Fallback: deliver damage via scripted projectiles with an asteroid look.
- **Counterplay:** more turrets, **point-defence lasers** (new turret tuned for showers), or wait it out.

### 6.3 Solar flares — *Should*

- Solar output spikes, then drops while panels recover; exposed electronics take minor damage.
- **How:** `LuaSurface.solar_power_multiplier` (writable, confirmed) on platform surfaces during the event; scripted damage for the electronics part.
- **Counterplay:** accumulators, non-solar power, or shielding (6.4).

### 6.4 Solar radiation near the sun — *Must*

Yes, this is possible. Every space location defines how strong sunlight is there (`SpaceLocationPrototype.solar_power_in_space`); Vulcanus orbit is much brighter than Aquilo's. Radiation uses the same number.

- **Exposure:** each platform gets a radiation level from its location (or, in transit, interpolated along the route using `LuaSpacePlatform.distance`). Above a threshold, unshielded entities take periodic damage of a new **radiation** damage type (`LuaEntity.damage`).
- **Shielding:**
  - **Radiation shield generator:** a powered building that protects everything within its radius. Power draw scales with exposure.
  - **Shielded foundation:** an upgraded platform tile; entities on it take reduced radiation damage.
  - **Radiation-hardened** variants are a balance option for later (resistances on the new damage type).
- **Why it's fun:** it makes the inner system a destination you prepare for, and gives Vulcanus-orbit platforms a reason to look different.
- **Performance:** damage is applied to a rotating slice of entities each tick, not all at once.

---

## 7. Module C — Asteroid Anchoring & Mining

A new resource loop in space: **large asteroids** drift into orbit at some locations, you anchor to one, mine it out, and release it.

### 7.1 How it works

1. **Spawning:** occasionally a large asteroid appears at a location (more at the solar system edge and around the shattered planet). It shows on the forecast panel with its size and composition (metallic, carbonic, oxide, rare).
2. **Anchoring:** a platform with an **anchor clamp** (a docking-port variant) docks to the asteroid. Under the hood the asteroid is a hidden "guest" made of **asteroid rock tiles**, and it reuses the docking code: fit check, merge, verify.
3. **Mining:** **asteroid drills** placed on the rock produce asteroid chunks (or ores for rare asteroids) until the asteroid is depleted. Depletion is tracked per asteroid.
4. **Release:** undock (or depletion) removes the rock; anything built on it is mined into the hub, just like a bridge.

### 7.2 Implementation options

| Option | How | Notes |
|---|---|---|
| **Simple (start here)** | Asteroid drills are crafting-machine entities that "mine" a fixed recipe while placed on rock tiles; script tracks remaining amount and stops them at depletion. | Reliable, no engine questions. |
| **Full** | Place real resource entities on the rock tiles and use a custom mining-drill prototype. | **Spike needed:** whether resources and drills work on platform surfaces. Nicer (vanilla drills UI, resource tooltips) if it does. |

### 7.3 Balance

- Large asteroids give far more than collectors, but require travelling to them, power for drills, and defence while anchored.
- Rare asteroids (edge of system) are the reason to go there.
- Anchored platforms can't leave until they release.

---

## 8. Module D — Derelicts

Things worth finding in space, built on the docking system.

### 8.1 How it works

1. **Distress beacons:** occasionally a beacon appears at a space location (alert + forecast panel entry). It expires after a while.
2. **Docking:** the derelict is a real hidden platform with wreckage, damaged machines, containers with loot, and sometimes inactive turrets. Fly there and **dock to it** with a docking port.
3. **Salvage:** deconstruct machines for parts, empty containers, recover rare items (blueprint-like "data cores" that unlock alternate recipes or cosmetic tiles).
4. **Undock** when done; the derelict is deleted when stripped or when its beacon expires.

### 8.2 Variety

| Type | Contents | Risk |
|---|---|---|
| Cargo hauler | Mostly items | None |
| Research vessel | Data cores | Low |
| Military wreck | Ammo, turrets you can repair and keep | Turrets reactivate if you dock carelessly |
| Trap beacon | Bait loot | Meteor shower triggered on dock, or the wreck explodes on a timer |

### 8.3 Generation

Derelicts are generated from **templates** (blueprint strings stored in the mod), randomly damaged and filled per spawn. Easy to add more templates later, and a good place for community contributions.

---

## 9. Gameplay loops

The stories for the Mod Portal page and the showcase video.

1. **The Tanker.** A slow fuel ship parks at Aquilo; light shuttles run to the surface and back to refuel. *(Docking, couplers, automation.)*
2. **The Carrier.** A warship flies to the shattered planet with three harvesters docked, **launches them on the way**, and collects them on the return. *(Carrier, in-flight launch.)*
3. **The Depot.** A permanent service station in orbit refuels and re-arms every visitor. *(Depot mode.)*
4. **The Storm Runner.** A schedule waits for a calm window, then dashes through a route before the next meteor shower. *(Forecast, circuits.)*
5. **The Sun Diver.** A shielded platform parks in Vulcanus orbit, protected by shield generators, to harvest extreme solar power. *(Radiation.)*
6. **The Miner.** A mining ship anchors to a rare asteroid at the system edge and mines it out while turrets hold off showers. *(Asteroid mining, weather.)*
7. **The Salvager.** A small, fast ship answers distress beacons and strips derelicts for data cores. *(Derelicts, docking.)*

---

## 10. Technology & progression

Draft tree; costs are tuned in the balance milestone.

| Technology | Unlocks | Prerequisites | Science (draft) |
|---|---|---|---|
| **Platform Docking** | Docking port, bridge | Space platform | Automation, logistic, space |
| **Docking Couplers** | Belt and fluid couplers | Platform Docking | + chemical |
| **Automated Docking** | Port circuit control, docking codes | Couplers, circuit network | + production |
| **Carrier Clamps** | Multiple guests, in-flight launch | Automated Docking | + electromagnetic |
| **Orbital Depot** | Depot mode | Carrier Clamps | + cryogenic |
| **Space Forecasting** | Forecast panel, hub forecast signals | Space platform | Automation, logistic, space |
| **Point Defence** | Point-defence laser | Forecasting, laser turret | + military |
| **Radiation Shielding** | Shield generator, shielded foundation | Forecasting | + metallurgic |
| **Asteroid Anchoring** | Anchor clamp, asteroid drills | Platform Docking, asteroid productivity | + space |
| **Deep Space Salvage** | Beacon detection, salvage bonuses | Platform Docking | + space |

---

## 11. Art, audio & presentation

All entity graphics in 2.0/2.1 are high-resolution only. Match Space Age's style (cool greys, warm hazard stripes, panel lines).

### 11.1 Sprites

| Module | Asset | Notes |
|---|---|---|
| A | **Docking port** | 4 directions, docking face obvious. Base, shadow, emissive lamp, clamp open/close animation (~16 frames), remnants. |
| A | **Belt / fluid / power couplers** | 4 directions, base + shadow + connector light. |
| A | **Bridge** | Grated deck tile with transitions + side trusses drawn via `LuaRendering` so it reads as a mechanical bridge. Extend animation segment. |
| A | **Docked-hub overlay** | "Hub offline" marker for the guest's hub spot. |
| B | **Point-defence laser** | Turret with base, shadow, rotating head, muzzle glow. |
| B | **Radiation shield generator** | Building with animated field emitter + shield radius rendering. |
| B | **Shielded foundation** | Tile variant of platform foundation. |
| B | **Meteor visual** | Re-tinted vanilla asteroid sprites with fiery trail (to tell shower meteors apart). |
| C | **Anchor clamp** | Docking-port variant with grappling claws. |
| C | **Asteroid rock tiles** | Metallic / carbonic / oxide / rare variants. |
| C | **Asteroid drill** | Base, shadow, drilling animation. |
| D | **Derelict wreckage** | Damaged variants of common entities, debris decoratives. |
| D | **Data core** | Item icon. |
| All | **Icons** | 64 × 64 items (with mipmaps), 256 × 256 technologies, GUI status icons, forecast weather icons. |

**Making them:** Blender, render each direction from the vanilla isometric angle, composite layers. `.blend` files are already excluded from release zips. Or commission an artist using this table as the brief.

### 11.2 Audio

Clamp engage, bridge extend loop, lock hiss, release, launch thrust, meteor impacts, radiation Geiger tick near unshielded entities, shield hum, distress beacon ping, alert chirps. Start with vanilla sounds and replace later.

### 11.3 Presentation

- **Thumbnail:** 144 × 144 PNG — a carrier with a docked guest, glowing bridge, sun flare behind.
- **Gallery:** one image per gameplay loop (section 9) + GIF of dock → fly → launch.
- **Video** (2–3 min): docking, carrier launch, storm runner waiting for a window, sun diver, mining an asteroid, salvaging a derelict.

---

## 12. Engineering work

### 12.1 Port to Factorio 2.1 — *Must, first*

Popular mods are moving to 2.1 and some authors have stopped making new 2.0 mods. Release on 2.1.

- [ ] Update `info.json` `factorio_version` and dependency versions.
- [ ] Re-check every API call against the 2.1 docs (clone_brush, set_tiles, platform attributes, GUI). The `factorio-ai-tools` docs search currently offers 2.0.76; prototypes search offers 2.1.8. Update `CLAUDE.md` research rules once 2.1 docs are available there.
- [ ] Re-run the full manual test checklist on 2.1.
- [ ] Decide whether to keep a 2.0 branch (recommendation: no).

### 12.2 Hardening

- [ ] Placement restriction and exclusion zone.
- [ ] Multiplayer (2+ clients) with no desyncs.
- [ ] Performance: dock a 5 000-entity guest; measure the spike.
- [ ] Clone check for platform entities with special state: asteroid collectors, crushers, thrusters, cargo bays, turrets with ammo, assemblers mid-craft.
- [ ] Behaviour when the guest's hub is destroyed while docked.
- [ ] Versioned migrations (`migrations/`) for every storage schema change.

### 12.3 Spikes (quick in-game experiments before committing)

| Spike | Unblocks |
|---|---|
| Write `distance` after `space_connection` | In-flight launch position (5.3) |
| Script-created asteroids behave like natural ones | Meteor showers (6.2) |
| Resource entities + mining drill on a platform surface | Full asteroid mining (7.2) |
| Is `LuaSpacePlatform.speed` writable | Transfer windows (parked, section 17) |
| Hidden platform as derelict: can players remote-view and dock to it | Derelicts (8.1) |

### 12.4 Compatibility

- Mods with per-entity state should handle `on_entity_cloned` (cloning raises it). Test with popular Space Age planet mods and platform-entity mods.
- Weather and radiation must leave other mods' platforms alone if they opt out (remote interface flag).
- **Known issue — Visible Planets** (the mod that draws the planet behind a platform in orbit): shows the wrong planet after docking. Likely cause: it reads the planet once per surface or misses our script changes to the guest's `space_location` while it's hidden. Investigate which events it listens to; fix on our side or report to its author.
- Public **remote interface** and **custom events** (`on_platform_docked`, `on_platform_undocked`, `on_guest_launched`, `on_weather_event`) for other mods.

---

## 13. Testing

| Layer | Tool | What |
|---|---|---|
| Syntax | `luaparse` / `luacheck` | Every `.lua` file on every change |
| Automated in-game | [FactorioTest](https://mods.factorio.com/mod/factorio-test) | Dock / undock / launch / anchor scenarios with entity-count checks |
| Manual | Release checklist | Full matrix per module before every release |
| Multiplayer | Local host + clients | Every module, with save/load |
| Performance | Large test save | Dock spikes, radiation damage cost, weather spawning cost |
| Community | Public beta on the portal | Discussion tab + GitHub issues |

---

## 14. Mod Portal & launch kit

### 14.1 `info.json`

- `name`: `super-space-age` (permanent).
- `title`: **Super Space Age**.
- `description`: *Dock and carry ships, launch them mid-flight, weather the storms, mine asteroids and salvage derelicts.*
- `factorio_version`: `2.1`. Dependencies: `base`, `space-age`.

### 14.2 Mod Portal page

- **Summary:** *Turn your platforms into a fleet: dock, carry and launch ships, plan around meteor showers and solar radiation, mine giant asteroids and salvage derelicts.*
- **Category:** Content. **Tags:** Logistics, Transportation, Circuit network, Environment.
- **Description sections:** hero GIF → what it adds (one line per module) → gameplay loops with images → how to use (per module) → "your items are never lost" → settings (including module toggles) → compatibility → for mod authors → credits.
- **FAQ:** multiplayer? docking in transit? what happens to the guest's hub? why can't my ports see each other (facing rule)? does docking slow my ship? can I turn off weather/radiation?
- **Changelog:** generated by semantic-release.

### 14.3 Release logistics

- [ ] `FACTORIO_TOKEN` in GitHub secrets.
- [ ] Work on `dev`; merge to `main` only to release (every push to `main` publishes).
- [ ] Rename the repo/mod folder to `super-space-age` before the first upload.
- [ ] English locale complete; community translations via PRs.
- [ ] Announce: r/factorio post with GIF, Factorio Discord `#mod-showcase`, forum thread; reach out to Factorio YouTubers with a mod spotlight pitch.

---

## 15. Milestones

Ship the docking module first so the mod gets players and feedback early; add the others as updates.

| # | Milestone | Contents | Exit criteria |
|---|---|---|---|
| **M0** | 2.1 port & hardening | 12.1, 12.2 | Checklist passes on 2.1; MP and big-save tested |
| **M1** | Carrier & launch | 5.2, 5.3 | Three guests on one host; launch mid-flight works |
| **M2** | Couplers & automation | 5.4, 5.5 | Fully automated tanker loop |
| **M3** | Docking art & balance | 5.1, 5.8, docking sprites, tech tree | No placeholder art in module A |
| **M4** | **Public beta 0.5** | Portal page, thumbnail, gallery | Published as *Super Space Age* (docking only) |
| **M5** | Weather & radiation | Module B | Storm Runner and Sun Diver loops playable |
| **M6** | Asteroid mining | Module C | Miner loop playable |
| **M7** | Derelicts | Module D | Salvager loop playable; 5+ templates |
| **M8** | **1.0** | Depot mode, polish, video | Two weeks with no data-loss bug reports |

Placeholder art is fine until each module's mechanics are locked.

---

## 16. Open decisions

| Question | Recommendation |
|---|---|
| One mod or several? | One mod (`super-space-age`) with startup toggles per module. |
| Call it a walkway or a bridge? | **Bridge.** Players don't walk on platforms in vanilla; it carries belts, pipes and inserters. |
| Radiation difficulty | Damage to players' builds can feel harsh. Ship it **on**, with an intensity setting (off / mild / normal / harsh). |
| Weather predictability | Seeded cycles per save, so forecasts are always right. |
| Asteroid mining approach | Start with the simple crafting-machine drills; switch to real resources if the spike succeeds. |
| Allied-force docking | Post-1.0. |
| Fluid coupler rate | Scale with quality. |
| Hub transfer | Keep a slow free transfer; couplers are the fast path. |

---

## 17. Parked ideas

- **In-flight rendezvous:** dock two platforms that are both travelling the same route.
- **Transfer windows:** periodic speed bonuses on routes during planetary alignment (depends on the `speed` spike).
- **Allied docking** for multiplayer teams.
- **Docking tugs:** tiny platforms that exist only to push others.
- **Platform templates:** save a docked combination as a preset.
- **Statistics & achievements:** fuel transferred, longest carrier trip, derelicts salvaged.
