#!/usr/bin/env bash
# Patch group call: camera/mic fallbacks + listen-only without capture devices.
# Rebuild client. Run inside LXC 103 as root (or via pct exec).
set -euo pipefail

cd /opt/owncord
FILE=client/src/hooks/useGroupCall.ts

python3 <<'PY'
from pathlib import Path

p = Path("client/src/hooks/useGroupCall.ts")
text = p.read_text()

# --- Block A: already patched (captureLocalMedia + camera fallback) ---
block_a_old = """        let rawStream;
        let gotVideo = !!wantVideo;
        try {
          rawStream = await captureLocalMedia({
            wantVideo: gotVideo,
            audioDeviceId: settings?.inputDeviceId,
          });
        } catch (err) {
          // Нет камеры при видеозвонке — пробуем только микрофон.
          if (
            gotVideo &&
            (err?.name === 'NotFoundError' || err?.name === 'OverconstrainedError')
          ) {
            toast?.info?.('Камера не найдена — подключаемся только с микрофоном');
            gotVideo = false;
            setWithVideo(false);
            rawStream = await captureLocalMedia({
              wantVideo: false,
              audioDeviceId: settings?.inputDeviceId,
            });
          } else {
            throw err;
          }
        }

        const rawMic = rawStream.getAudioTracks()[0] || null;
        videoTrackRef.current = rawStream.getVideoTracks()[0] || null;

        // Прогоняем микрофон через AudioContext-pipeline (HighPass →"""

# --- Block B: pristine upstream (inline getUserMedia) ---
block_b_old = """        const audioConstraint = {
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
          ...(settings?.inputDeviceId && settings.inputDeviceId !== 'default'
            ? { deviceId: { exact: settings.inputDeviceId } }
            : {}),
        };
        let rawStream;
        try {
          rawStream = await navigator.mediaDevices.getUserMedia({
            audio: audioConstraint,
            video: wantVideo ? { width: { ideal: 1280 }, height: { ideal: 720 } } : false,
          });
        } catch (err) {
          // Если deviceId стал невалидным (микрофон сменили/отключили) —
          // пробуем без exact-deviceId, иначе вызов ляжет в OverconstrainedError.
          if (err?.name === 'OverconstrainedError' || err?.name === 'NotFoundError') {
            rawStream = await navigator.mediaDevices.getUserMedia({
              audio: {
                echoCancellation: true,
                noiseSuppression: true,
                autoGainControl: true,
              },
              video: wantVideo ? { width: { ideal: 1280 }, height: { ideal: 720 } } : false,
            });
          } else {
            throw err;
          }
        }

        const rawMic = rawStream.getAudioTracks()[0] || null;
        videoTrackRef.current = rawStream.getVideoTracks()[0] || null;

        // Прогоняем микрофон через AudioContext-pipeline (HighPass →"""

block_new = """        let rawStream = null;
        let listenOnly = false;
        let gotVideo = !!wantVideo;
        const noCaptureDevice = (e) =>
          e?.name === 'NotFoundError' ||
          e?.name === 'OverconstrainedError' ||
          e?.name === 'NotAllowedError';

        try {
          rawStream = await captureLocalMedia({
            wantVideo: gotVideo,
            audioDeviceId: settings?.inputDeviceId,
          });
        } catch (err) {
          if (gotVideo && noCaptureDevice(err)) {
            toast?.info?.('Камера не найдена — подключаемся только с микрофоном');
            gotVideo = false;
            setWithVideo(false);
            try {
              rawStream = await captureLocalMedia({
                wantVideo: false,
                audioDeviceId: settings?.inputDeviceId,
              });
            } catch (err2) {
              if (noCaptureDevice(err2)) {
                listenOnly = true;
                toast?.info?.(
                  'Микрофон недоступен — режим прослушивания (микрофон выключен)',
                );
              } else {
                throw err2;
              }
            }
          } else if (noCaptureDevice(err)) {
            listenOnly = true;
            toast?.info?.(
              'Микрофон недоступен — режим прослушивания (микрофон выключен)',
            );
          } else {
            throw err;
          }
        }

        let rawMic = null;
        videoTrackRef.current = null;
        if (listenOnly) {
          if (!placeholderAudioRef.current) {
            placeholderAudioRef.current = createPlaceholderAudioTrack();
          }
          const ph = placeholderAudioRef.current;
          ph.enabled = false;
          audioTrackRef.current = ph;
          setMuted(true);
        } else {
          rawMic = rawStream.getAudioTracks()[0] || null;
          videoTrackRef.current = rawStream.getVideoTracks()[0] || null;
        }

        // Прогоняем микрофон через AudioContext-pipeline (HighPass →"""

# --- Already has listen-only (idempotent) ---
listen_marker = "let listenOnly = false;"

if listen_marker in text:
    print("already patched (listen-only)", p)
elif block_a_old in text:
    text = text.replace(block_a_old, block_new, 1)
    print("patched from block A", p)
elif block_b_old in text:
    text = text.replace(block_b_old, block_new, 1)
    print("patched from block B", p)
else:
    raise SystemExit("join media block not found — OwnCord version mismatch?")

# Pipeline + local stream: skip overwriting placeholder in listen-only mode
pipe_old = """        }
        audioTrackRef.current = processedMic;

        const ls = new MediaStream();
        if (processedMic) ls.addTrack(processedMic);
        if (videoTrackRef.current) ls.addTrack(videoTrackRef.current);
        localStreamRef.current = ls;
        if (videoTrackRef.current) setCameraOn(true);
        setLocalStream(ls);

        // Отправляем серверу запрос на присоединение"""

pipe_new = """        }
        if (!listenOnly) {
          audioTrackRef.current = processedMic;
        }

        const ls = new MediaStream();
        if (audioTrackRef.current) ls.addTrack(audioTrackRef.current);
        if (videoTrackRef.current) ls.addTrack(videoTrackRef.current);
        localStreamRef.current = ls;
        if (videoTrackRef.current) setCameraOn(true);
        setLocalStream(ls);
        if (listenOnly) {
          setTimeout(emitMyMedia, 0);
        }

        // Отправляем серверу запрос на присоединение"""

if listen_marker not in text or pipe_old in text:
    if pipe_old not in text:
        raise SystemExit("pipeline/localStream block not found")
    text = text.replace(pipe_old, pipe_new, 1)
    print("patched pipeline block", p)

# withVideo in join ack should reflect gotVideo after fallbacks
join_emit_old = "{ groupId: targetGroup.id, withVideo: !!wantVideo },"
join_emit_new = "{ groupId: targetGroup.id, withVideo: !!gotVideo },"
if join_emit_old in text:
    text = text.replace(join_emit_old, join_emit_new, 1)
    print("patched groupcall:join withVideo", p)

# Friendlier error toast (device errors handled above)
catch_old = """        const errName = e?.name || '';
        const hint =
          errName === 'NotFoundError'
            ? 'микрофон или камера не найдены (Настройки → Аудио, устройство записи в Windows)'
            : errName === 'NotAllowedError'
              ? 'доступ к микрофону запрещён в браузере'
              : e?.message || String(e);
        toast?.error?.(`Не удалось присоединиться: ${hint}`);"""

catch_new = """        const hint = e?.message || String(e);
        toast?.error?.(`Не удалось присоединиться: ${hint}`);"""

if catch_old in text:
    text = text.replace(catch_old, catch_new, 1)
    print("patched error toast", p)
elif "toast?.error?.(`Не удалось присоединиться: ${e.message || e}`);" in text:
    text = text.replace(
        "toast?.error?.(`Не удалось присоединиться: ${e.message || e}`);",
        catch_new,
        1,
    )
    print("patched error toast (upstream)", p)

p.write_text(text)
PY

npm run build
systemctl restart owncord
echo '[owncord-patch-voice-media] done'
