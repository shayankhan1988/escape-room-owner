# Escape Room Owner

Build escape rooms. Watch strangers fail them. Clean up the mess.

A first-person management simulator made with [Godot 4](https://godotengine.org/).

## Play the current build

1. Install **Godot 4.4** (standard version, not .NET): https://godotengine.org/download
2. Open Godot, click **Import**, and pick `project.godot` from this folder.
3. Press **F5** (or the ▶ button top right) to play.

### Controls

| Key | Action |
|---|---|
| WASD / arrows | Walk |
| Mouse | Look around (click the window first) |
| E or left click | Use what you are looking at |
| Tab | Change time speed during a session |
| 1, 2, 3 | Switch security camera |
| F | Flashlight |
| Esc | Free the mouse |

### How a round works

1. **Lobby:** a group of customers is waiting. Walk into *The Study* and press E on a pedestal to swap its puzzle (new puzzles cost money).
2. **Open the room:** go to the control room and press the green **OPEN ROOM** button on the desk.
3. **Session:** watch the customers on the CCTV monitor. When they get stuck, the red **INTERCOM** button flashes: press it to give a hint. Too many hints cost stars.
4. **Review:** you get a review and money. Groups that escape just before the timer runs out give 5 stars.
5. **Reset:** walk into the room, clean up the mess and repair broken puzzles. Then the next group arrives.

Progress is saved automatically.

## Project layout

- `scripts/main.gd` builds the venue and runs the game loop (state, customers, sessions, reviews, reset).
- `scripts/player.gd` is the first-person controller and interaction ray.
- `scripts/customer.gd` is a customer that walks between waypoints.
- `scripts/interactable.gd` is anything you can press E on.
- `tests/smoke_test.gd` plays six groups headlessly: `godot --headless -s tests/smoke_test.gd`

This is a **graybox**: everything is made of simple blocks so the gameplay can be tuned first. Art (CC0 low-poly assets) comes next.
