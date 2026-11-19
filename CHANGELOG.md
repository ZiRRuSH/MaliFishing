# Changelog

## v0.1b

First non-alpha release.

### Fixed

- Fresh-catch auto-opening now retries briefly if the container hasn’t appeared in your bags yet. Tested in-game: the next fishing press opened a freshly caught trunk.
- Container eligibility still uses the game’s `hasLoot` flag, with no hardcoded item IDs or whitelist. Locked containers and older bag stock are left alone.

### HUD improvements

- Added a border thickness setting for the regular HUD.
- Added separate controls for border visibility, color, and thickness in Minimal HUD Settings.
- Added a target catch icon size slider for the minimal HUD.
