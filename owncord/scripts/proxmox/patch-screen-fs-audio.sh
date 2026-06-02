#!/usr/bin/env bash
# OwnCord homelab: screen-share audio fallback + fullscreen on tiles + default screen audio on.
# Run inside LXC 103 as root.
set -euo pipefail

cd /opt/owncord

python3 <<'PY'
from pathlib import Path

# --- useGroupCall.ts ---
ug = Path("client/src/hooks/useGroupCall.ts")
text = ug.read_text()

if "listenOnlyRef" not in text:
    text = text.replace(
        "  const placeholderVideoRef = useRef(null);\n",
        "  const placeholderVideoRef = useRef(null);\n"
        "  const listenOnlyRef = useRef(false);\n",
        1,
    )
    print("added listenOnlyRef")

if "getOutboundAudioTrack" not in text:
    anchor = "  const currentVideoTrack = () => screenTrackRef.current || videoTrackRef.current;\n"
    helper = """  const currentVideoTrack = () => screenTrackRef.current || videoTrackRef.current;

  // Исходящий audio для WebRTC: микшер mic+screen → только звук стрима → мик/placeholder.
  const getOutboundAudioTrack = () => {
    const mixed = micScreenMixerRef.current?.outputTrack || null;
    if (mixed) return mixed;
    if (screenTrackRef.current && screenAudioTrackRef.current) {
      return screenAudioTrackRef.current;
    }
    return audioTrackRef.current || null;
  };

"""
    if anchor not in text:
        raise SystemExit("currentVideoTrack anchor missing")
    text = text.replace(anchor, helper, 1)
    print("added getOutboundAudioTrack")

old_apply = """    const mixedAudio = micScreenMixerRef.current?.outputTrack || null;
    let aTrack = mixedAudio || audioTrackRef.current;
    if (!aTrack) {
      if (!placeholderAudioRef.current) {
        placeholderAudioRef.current = createPlaceholderAudioTrack();
      }
      aTrack = placeholderAudioRef.current;
    }"""

new_apply = """    let aTrack = getOutboundAudioTrack();
    if (!aTrack) {
      if (!placeholderAudioRef.current) {
        placeholderAudioRef.current = createPlaceholderAudioTrack();
      }
      aTrack = placeholderAudioRef.current;
    }"""

if old_apply in text:
    text = text.replace(old_apply, new_apply, 1)
    print("patched applyLocalTracksToPc")
elif new_apply.split("\n")[1] in text:
    print("applyLocalTracksToPc already patched")
else:
    raise SystemExit("applyLocalTracksToPc block not found")

old_pc = "      const aTrack = micScreenMixerRef.current?.outputTrack || audioTrackRef.current;"
new_pc = "      const aTrack = getOutboundAudioTrack();"
if old_pc in text:
    text = text.replace(old_pc, new_pc, 1)
    print("patched createPeerConnection audio")
elif new_pc in text:
    print("createPeerConnection already patched")
else:
    raise SystemExit("createPeerConnection audio line not found")

if "listenOnlyRef.current = true" not in text:
    text = text.replace(
        "          setMuted(true);\n        } else {",
        "          setMuted(true);\n          listenOnlyRef.current = true;\n        } else {",
        1,
    )
    print("listenOnlyRef set on join")

if "listenOnlyRef.current = false" not in text:
    text = text.replace(
        "    setMuted(false);\n    setDeafened(false);",
        "    setMuted(false);\n    listenOnlyRef.current = false;\n    setDeafened(false);",
        1,
    )
    print("listenOnlyRef cleared on cleanup")

old_mixer_if = "        if (audioTrackRef.current) {\n          try {\n            if (micScreenMixerRef.current) {"
new_mixer_if = """        if (audioTrackRef.current && !listenOnlyRef.current) {
          try {
            if (micScreenMixerRef.current) {"""
if old_mixer_if in text:
    text = text.replace(old_mixer_if, new_mixer_if, 1)
    print("patched screen mixer gate (listen-only → screen audio only)")
elif new_mixer_if.split("\n")[0] in text:
    print("screen mixer gate already patched")
else:
    raise SystemExit("screen mixer if block not found")

# Toast when user asked for screen audio but browser gave none
marker = "      const audioTrack = display.getAudioTracks()[0];\n"
toast_block = """      const audioTrack = display.getAudioTracks()[0];
      if (includeAudio && !audioTrack) {
        toast?.info?.(
          'Звук экрана не захвачен. В диалоге браузера включите «Поделиться звуком» или выберите весь экран / вкладку с галочкой звука.',
        );
      }
"""
if marker in text and "Звук экрана не захвачен" not in text:
    text = text.replace(marker, toast_block, 1)
    print("added missing screen-audio toast")

ug.write_text(text)

# --- GroupCallView.tsx ---
gv = Path("client/src/components/GroupCallView.tsx")
gtext = gv.read_text()

for old in (
    """          speaking={!muted && speaks(selfId)}
          className={opts.className}
        />""",
    """        speaking={speaks(t.userId)}
        className={opts.className}
      />""",
):
    pass

old_self = """          speaking={!muted && speaks(selfId)}
          className={opts.className}
        />"""
new_self = """          speaking={!muted && speaks(selfId)}
          fullscreenable
          className={opts.className}
        />"""
if old_self in gtext and "fullscreenable" not in gtext[gtext.find(old_self) : gtext.find(old_self) + 120]:
    gtext = gtext.replace(old_self, new_self, 1)
    print("GroupCallView self fullscreenable")

old_peer = """        speaking={speaks(t.userId)}
        className={opts.className}
      />"""
new_peer = """        speaking={speaks(t.userId)}
        fullscreenable
        className={opts.className}
      />"""
if old_peer in gtext:
    gtext = gtext.replace(old_peer, new_peer, 1)
    print("GroupCallView peer fullscreenable")
elif "fullscreenable" in gtext and "renderTile" in gtext:
    print("GroupCallView fullscreenable already set")

gv.write_text(gtext)

# --- ScreenQualityModal.tsx ---
sq = Path("client/src/components/ScreenQualityModal.tsx")
stext = sq.read_text()
if "useState(false)" in stext and "includeAudio" in stext:
    stext2 = stext.replace(
        "const [includeAudio, setIncludeAudio] = useState(false);",
        "const [includeAudio, setIncludeAudio] = useState(true);",
        1,
    )
    if stext2 != stext:
        sq.write_text(stext2)
        print("ScreenQualityModal default includeAudio=true")
    else:
        print("ScreenQualityModal already true")
PY

npm run build
systemctl restart owncord
echo '[owncord-patch-screen-fs-audio] done'
