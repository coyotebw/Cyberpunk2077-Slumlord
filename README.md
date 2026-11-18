# Slumlord

Cyberpunk 2077 mod (game version 2.5, PC). V becomes a landlord: buys property across Night City, collects rent, squeezes tenants and takes on rival landlords. Modelled on Yakuza 0's Real Estate Royale.

Status: Phase 1, in development. Not yet released.

## Layout

| Path | Contents |
|---|---|
| `mod/` | Files installed into the game folder, game-relative (`r6/scripts/Slumlord`, `r6/audioware/Slumlord`, CET debug tool, `Slumlord.archive.xl`) |
| `wolvenkit/` | WolvenKit project: `source/archive` (CR2W files packed into `Slumlord.archive`), `source/raw` (JSON and PNG sources) |
| `tools/` | Generators (colours, journal, world sector, icons, voice) |

## Requirements

Cyber Engine Tweaks 1.38.0 · RED4ext 1.31.0 · redscript 0.5.32 · ArchiveXL 1.28.0 · TweakXL 1.12.0 · Codeware 1.21.0 · Audioware (optional: voice).
Optional: Browser Extension Framework, Night City Allies.

## Building the archive

WolvenKit CLI 10.0.0-beta.1 (.NET 10) packs and converts on Linux and Windows:

```
dotnet tool install -g WolvenKit.CLI --version 10.0.0-beta.1
cp77tools convert d wolvenkit/source/raw/slumlord      # JSON -> CR2W
cp77tools pack wolvenkit/source/archive -o build        # -> build/archive.archive, rename to Slumlord.archive
```

PNG → `.xbm` texture import works only on Windows (WolvenKit GUI Import Tool, `TEXG_Generic_UI`).

## Install (dev)

Copy the contents of `mod/` into `Cyberpunk 2077/`, and `Slumlord.archive` into `archive/pc/mod/`.
