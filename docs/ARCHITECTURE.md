# Architecture

## Rojo mapping (`default.project.json`)

| Roblox location | Repo path |
|---|---|
| `ReplicatedStorage.Shared` | `src/shared/` (modules used by both sides) |
| `ReplicatedStorage.CarMeshes` | `assets/CarMeshes.rbxmx` (all car MeshParts, one per mesh object name) |
| `ReplicatedFirst.Loading` | `src/first/Loading.client.luau` |
| `ServerScriptService.Server` | `src/server/` (`init.server.luau` is the Script, the rest are ModuleScripts) |
| `StarterPlayer.StarterPlayerScripts.Client` | `src/client/` (`init.client.luau` is the LocalScript) |

`Players.CharacterAutoLoads = false`: there are no avatars walking around. Players live in menus and cars.

## Server (`src/server/`)

- **init.server.luau**: entry point.
  - Wires the services.
  - Binds every `Net.Functions` remote through `bind()`, which adds rate limiting and pcall with friendly errors.
  - Holds the profile, garage and shop handlers (`GetProfile`, `BuyItem`, `Equip`, `SetNumber`, `ClaimDaily`, `SaveSettings`).
  - Equipping a `Body` item also applies that chassis's default colours (`Cosmetics.BodyLivery`).
- **DataService**: player profiles in DataStore `Config.DataStores.Player`, with session locking, autosave and a safe shutdown. Saving is off in Studio without API access.
- **RaceManager**: runs lobbies, races and results.
  - Lobbies: Quick Race, Ranked with a map vote between 3 circuits, private lobbies.
  - Starts a session, fills empty Quick Race slots with computer drivers (`aiCar`, `stepAI`; never in Ranked), validates gates and laps, relays car states, handles contact and bumps.
  - Sends standings, ends the race and pays rewards and ranked RP. With fewer than 10 ranked racers the `PositionRP` table is stretched, so last place always gets the last-place RP.
  - Ranked never starts with fewer than `Config.Ranked.Queue.MinRacers` (2) real players. In Studio the local ranked lobby just keeps waiting for a second player.
- **RankedMatchmaker**: ranked is real players only, matched across servers.
  - Lobby servers write queued players to a MemoryStore sorted map (`GTR_RankedQueue`, sorted by RP). One server at a time holds a short lock (`GTR_RankedLock`) and groups the queue with `FormMatches`: a full grid at once, fewer players the longer the oldest has waited (`Queue.Steps`), inside an RP window that widens every second.
  - Each match gets `TeleportService:ReserveServer`; the match is written per player to `GTR_RankedMatch`, and every lobby server teleports its own matched players there (profiles are saved and released first with `DataService.ReleaseForTeleport`).
  - A reserved server with `PrivateServerOwnerId == 0` is a match server: players arrive with the match in their teleport data, `RaceManager.MatchPlayer` puts them in one ranked lobby (vote starts early once everyone is in, `MatchWait` 30 s at most), and after the results everyone is teleported back to a public server. A match nobody else reached is cancelled with no RP lost; latecomers and strangers are sent back.
  - In Studio (no teleports or MemoryStore) it switches itself off and RaceManager's local ranked lobby is used.
- **TimeTrial**: validates every lap on the server. A lap must pass every gate and have a sane time. It stores ghosts and awards medals.
- **LeaderboardService**: OrderedDataStores for TT lap records per circuit, ranked RP, wins and level, with caching.
- **MonetizationService**: pass ownership, `ProcessReceipt` for dev products, and perk multipliers. In Studio every pass is granted if `Config.StudioGrantAllPasses`.
- **ChallengeService**: counts weekly-challenge progress from race results, Time Trial laps and Garage changes, pays claimed rewards, and adds the featured-circuit coin bonus. Rules (week number, featured circuit, challenge pool) are in `shared/Challenges.luau`, so every server agrees without any update.

## Client (`src/client/`)

- **init.client.luau**: bootstrap. Shows the menu, reacts to lobby and race events, starts races and time trials, shows results. It also creates the Studio-only `GoTrackDev` hook.
- **State**: cache of the player's profile and settings. The server is authoritative.
- **CarController**: arcade raycast-suspension car, simulated on the client for instant response.
  - Input: keyboard, gamepad and touch.
  - Handles damage visuals.
  - Animates the steering wheel and its screen (gear, speed, rev bar).
- **CameraController**: views `chase_near`, `chase_far`, `tcam`, `cockpit`, `nose` and `tv` (C cycles), plus the garage orbit.
  - Cockpit/tcam/nose offsets come from chassis attributes (`CockpitCam`, `TCam`, `NoseCam`) set by CarBuilder.
  - Cockpit view hides the helmet and collar.
- **RaceClient**: builds the circuit (behind the circuit intro), puts you on the grid, runs the start countdown, counts laps, sends gates and car state.
- **RemoteCars**: draws the other cars from the server's position stream (interpolated).
- **CircuitBuilder / Architecture**: build the whole circuit world on the client: road, kerbs, barriers, grandstands, themed buildings, horizon, weather and ambient effects.
- **Landmarks**: each circuit's signature sights (3-6 per circuit, many animated) and the boats, planes, birds, balloons and jets around it.
- **WorldLife**: city street grids with traffic and pedestrians, farm fields, spectator banks and the TV helicopter. All moving scenery is animated with one `BulkMoveTo` per frame.
- **Cityscape**: fills the rest of the land out to the horizon by layout (city grids with downtowns, suburbs, villages and forests, rock formations), within a part budget per Graphics Quality.
- **WorldMeshes** (+ generated `shared/WorldData`): places the Blender world meshes from `tools/worldgen` (buildings, trees, mountains, road cars). When `ReplicatedStorage.WorldMeshes` is empty everything falls back to part-built scenery. See `docs/WORLD_PIPELINE.md`.
- **UI/CircuitIntro**: the TV-style circuit presentation shown while the circuit builds, then a camera flyover until the lights.
- **UI/ChallengesPanel**, **UI/Onboarding**: weekly challenges window; welcome tour and first-race tips.
- **TimeTrialClient / GhostPlayer**: solo laps, ghost replay, medals.
- **RacingLine**: optional chevron racing line.
- **Fx**: sounds, rainbow paint, celebrations.
- **PerfOverlay**: FPS and ping display, auto-lowers graphics on weak devices.
- **UI/**: every screen, built with `Kit.luau` (the design system).

## Shared (`src/shared/`)

- **Config**: every tunable value.
- **Net**: remote names. Remotes are created by the server under `ReplicatedStorage.Remotes`.
- **Circuits / Track / Themes**: the calendar, pure geometry maths, and the look of each circuit.
- **CircuitInfo**: facts per circuit (km, corners, braking zones, difficulty stars) for the menus and the intro.
- **Challenges**: weekly featured circuit, weekly challenges and the getting-started checklist, all derived from the UTC week.
- **Cosmetics**: every item with its coin price or pass, `DefaultCar`, and `BodyLivery` (default colours per chassis).
- **CarBuilder**: builds a car Model from an appearance table using the meshes in `ReplicatedStorage.CarMeshes` and the layout in `CarData`. It falls back to `BuildLegacy` (block car) if meshes are missing.
- **CarData**: GENERATED. It holds:
  - mesh object centres and sizes;
  - per-design anchors (wheels, head, cams, steering wheel, number plates);
  - chassis → design presets.
- **Monetization**: pass and product data (IDs, prices, perks).
- **Medals**: medal thresholds.

## Remotes (`Net.luau`)

- Functions:
  - `GetProfile`, `BuyItem`, `Equip`, `SetNumber`, `ClaimDaily`, `SaveSettings`, `ClaimChallenge`, `SetFlag`
  - `GetLobbies`, `QuickRace`, `RankedQueue`, `JoinLobby`, `LeaveLobby`, `StartNow`, `VoteMap`
  - `TTStart`, `TTSubmitLap`, `GetLeaderboard`, `GetGhost`
- Events:
  - `ProfileUpdated`, `Notify`, `LobbyUpdate`
  - `RaceStart`, `RaceGate`, `RaceStandings`, `RaceResults`, `RaceLeave`, `RaceReset`
- Unreliable: `CarState`, `CarStates`, `Bump`

To add a remote:

1. Add its name to the right list in `Net.luau`.
2. Handle it on the server. For functions, use `bind("Name", fn)` in `init.server.luau`.
3. Call it from the client with `Util.Invoke("Name", ...)` or `Net.Event("Name")`.

## Race lifecycle

1. The player picks Quick Race or Ranked. Quick Race creates or joins a lobby, which counts down (`Config.Race.QuickCountdown` 20 s). Ranked joins the cross-server queue ("Searching for rivals"), then teleports to a match server where the lobby votes on the circuit (in Studio: a local ranked lobby, 25 s, that waits for a second real player).
2. `startSession`: the map vote resolves, Quick Race fills up to `Config.Race.MaxRacers` (10) with computer drivers (Ranked never does), and `RaceStart` goes out with the grid.
3. The client builds the circuit (`LoadTime` 9 s), then a 3 · 2 · 1 red-light countdown (`CountdownSeconds`) and green GO. Everyone is released at the same instant, and contact is ghosted for the first 3 s (`Config.Contact.GhostStartSeconds`).
4. The client streams `CarState` (20 Hz) and sends gate crossings. The server validates them and broadcasts `CarStates` and standings.
5. After the first real finisher there's a `FinishGrace` of 40 s. Then `endSession` pays coins and XP, updates ranked RP and history, and sends `RaceResults`.

## Data

The profile (DataService) holds:

- coins, xp/level and stats;
- owned items and the equipped car appearance;
- settings, daily streak and ranked RP/season;
- TT personal bests and medals.

DataStore names are in `Config.DataStores`. Don't rename them.
