#!/usr/bin/env bash
# Generate the encounter quest files (tools/quest/make_scenes.py), convert them to CR2W and move them into the
# WolvenKit archive tree. Then pack as usual: cp77tools pack wolvenkit/source/archive -o <dir>, and rename
# archive.archive to build/Slumlord.archive.
set -euo pipefail
cd "$(dirname "$0")/../.."
python3 tools/quest/make_scenes.py > /dev/null
RAW=wolvenkit/source/raw/slumlord
ARC=wolvenkit/source/archive/slumlord
FILES=(
  quest/slumlord_motel.questphase
  quest/scenes/slumlord_co_standoff.scene
  quest/scenes/slumlord_co_truce.scene
  world/sectors/slumlord_motel.streamingsector
  quest/slumlord_harbor.questphase
  quest/scenes/slumlord_fc_talk.scene
  quest/scenes/slumlord_fc_flee.scene
  world/sectors/slumlord_harbor.streamingsector
  world/slumlord.streamingblock
  localization/en-us.json
  localization/en-us/subtitles/slumlord_subtitles.json
  localization/en-us/subtitles/slumlord_subtitle_map.json
)
for f in "${FILES[@]}"; do
  cp77tools convert d "$RAW/$f.json" > /tmp/convert.log 2>&1 || { cat /tmp/convert.log; exit 1; }
  grep -q "Converted" /tmp/convert.log || { echo "$f"; cat /tmp/convert.log; exit 1; }
  mkdir -p "$(dirname "$ARC/$f")"
  mv "$RAW/$f" "$ARC/$f"
done
echo "encounter quest files converted into $ARC"
