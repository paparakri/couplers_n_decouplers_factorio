# Platform Docking

A Factorio 2.0 / Space Age mod that lets two space platforms parked at the same location dock into one, joined by a walkway, and fly together while docked. Use it to build big "tanker" platforms that carry smaller ships where they need to go.

## How it works

1. Research **Platform Docking** (space science) and build a **Docking Port** on the edge of each platform. The two ports must face each other (e.g. one east, one west); the target list only shows ports that do.
2. Open a port, pick a target port, and set the walkway's **length** and **width**. The preview line shows which platform hosts and whether it fits.
3. Press **Initiate Docking**. After a short countdown the smaller platform (the guest) is copied onto the larger one (the host), joined by the walkway. The guest's hub stays behind, marked by an overlay. Anyone viewing the guest is moved to the host.
4. While docked, the host can fly and carries the guest with it. The two hubs fill each other's logistic requests.
5. Press **Undock** on either port to split them again. Players viewing the guest's part go back with it. If the host is in transit, undocking finishes when it next stops. Anything built across the walkway goes into the host's hub.

Docking checks that the guest fits before changing anything, and both docking and undocking verify every entity was copied before removing the originals. If something doesn't match, nothing is lost: docking rolls back, and undocking leaves the platforms docked.

If a docking port is destroyed or a platform is deleted while docked, the platforms undock automatically.

## Settings

| Setting | Default | |
|---|---|---|
| Transfer rate | 10 | Items per tick moved between hubs |
| Docking countdown | 120 ticks | Delay before the platforms join |
| Allow flying while docked | on | If off, the host is paused while docked |
| Default corridor length | 6 | Walkway length (1–10); can be changed per dock in the port window |
| Default corridor width | 1 | Walkway width (1–9); can be changed per dock in the port window |

## Releasing

Pushing to `main` runs `.github/workflows/release.yml`, which publishes to the Factorio Mod Portal using [semantic-release-factorio](https://github.com/fgardt/semantic-release-factorio) and conventional commit messages.
