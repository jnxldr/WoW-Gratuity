# Building and releasing

The repository root is the add-on folder: copy it to `World of Warcraft\_forever_\Interface\AddOns\Gratuity\` to run it
from source (the version then shows as `@project-version@`).

## Releasing
1. Add a section for the new version at the top of `CHANGELOG.md` (`## 2.1.2`) and test in game.
2. Run `.\release.ps1 2.1.2` (PowerShell; `-DryRun` shows what it would do). It checks the version, branch, changelog
   section, commit email and Lua strings (`tools/lua_strcheck.py`, needs Python), asks, commits what is left, pushes `main`,
   creates and pushes the tag, then follows the upload (with the GitHub CLI `gh`). By hand it is
   `git tag -a 2.1.2 -m "Gratuity 2.1.2"` and `git push origin main 2.1.2`. Tags have no `v` (the tag becomes `## Version` as
   it is; tags before 2.0.3 had one).
3. The *Release* workflow (`.github/workflows/release.yml`) runs the
   [BigWigs packager](https://github.com/BigWigsMods/packager): it writes the tag into `## Version`, builds
   `Gratuity-<version>.zip` (folder `Gratuity/`, without the files listed under `ignore` in `.pkgmeta`) and uploads it to
   CurseForge, Wago and WoWInterface (projects named by `X-Curse-Project-ID`, `X-Wago-ID`, `X-WoWI-ID` in the `.toc`) and to a
   GitHub release. The changelog is the `CHANGELOG.md` section.

Tags with `alpha` or `beta` in them are uploaded as alpha/beta releases.

Repository secrets used: `CF_API_TOKEN`, `WAGO_API_TOKEN`, `WOWI_API_TOKEN` (GitHub's own token is built in). A site without
a project ID in the `.toc` or without a token is skipped.

## Data
`Data.lua` (which spells are enchants, their slot and reagents) is generated from the game's own DB2 tables for the client
build named in it. In game, names, icons and reagents are read from the client; `/gratuity check` compares the two after a patch.
