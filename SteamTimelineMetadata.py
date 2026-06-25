import json
import os
import subprocess
import sys
import threading
import time

import obspython as obs

PIPE_NAME = r"\\.\pipe\SteamTimeline"


class State:
	def __init__(self):
		self.events: list = []
		self._pending_ranges: dict = {}
		self._lock = threading.Lock()
		self._recording_start_t = None
		self.output_dir = ""
		self.replay_duration = 120.0
		self.ffmpeg_path = "ffmpeg"
		self.delay = 2.0
		self._pipe_stop = False
		self._pipe_thread = None
		self._tick_acc = 0.0

	def pipe_start(self):
		self._pipe_stop = False
		self._pipe_thread = threading.Thread(target=self._pipe_worker, daemon=True, name="SteamTimeline-Pipe")
		self._pipe_thread.start()

	def pipe_stop(self):
		self._pipe_stop = True

	def _pipe_worker(self):
		while not self._pipe_stop:
			try:
				with open(PIPE_NAME, "rb", buffering=0) as f:
					print("[SteamTimeline] Named pipe connected")
					buf = b""
					while not self._pipe_stop:
						try:
							chunk = f.read(4096)
						except OSError:
							break
						if not chunk:
							break
						buf += chunk
						while b"\n" in buf:
							line, buf = buf.split(b"\n", 1)
							line = line.strip()
							if line:
								self._process_line(line)
				print("[SteamTimeline] Pipe disconnected")
			except OSError:
				pass
			if not self._pipe_stop:
				time.sleep(1)

	def _process_line(self, raw: bytes):
		try:
			msg = json.loads(raw)
		except Exception as e:
			print(f"[SteamTimeline] Failed to parse JSON: {e} | Raw: {raw!r}")
			return
		evt_type = msg.get("type", "")
		data = msg.get("data", {})
		now = time.time()
		evt = self._map_event(evt_type, data, now)
		if evt is None:
			return
		with self._lock:
			self.events.append(evt)

	def _map_event(self, evt_type: str, data: dict, now: float):
		if evt_type == "AddInstantaneousTimelineEvent":
			return {
				"type": "instant",
				"t": now,
				"title": data.get("title", ""),
				"desc": data.get("description", ""),
				"icon": data.get("icon", ""),
				"pri": data.get("priority", 0),
				"clip": data.get("clipPriority", 0),
				"handle": data.get("handle", 0),
			}
		if evt_type == "AddRangeTimelineEvent":
			return {
				"type": "range",
				"t": now,
				"title": data.get("title", ""),
				"desc": data.get("description", ""),
				"icon": data.get("icon", ""),
				"pri": data.get("priority", 0),
				"dur": data.get("duration", 0.0),
				"clip": data.get("clipPriority", 0),
				"handle": data.get("handle", 0),
			}
		if evt_type == "StartRangeTimelineEvent":
			handle = data.get("handle", 0)
			with self._lock:
				self._pending_ranges[handle] = {
					"t": now,
					"title": data.get("title", ""),
					"desc": data.get("description", ""),
					"icon": data.get("icon", ""),
					"pri": data.get("priority", 0),
					"clip": data.get("clipPriority", 0),
				}
			return None
		if evt_type == "EndRangeTimelineEvent":
			handle = data.get("handle", 0)
			end_offset = data.get("endOffset", 0.0)
			with self._lock:
				pending = self._pending_ranges.pop(handle, None)
			if not pending:
				print(f"[SteamTimeline] Warning: EndRange for unknown handle {handle}")
				return None
			dur = (now - pending["t"]) + end_offset
			return {
				"type": "range",
				"t": pending["t"],
				"title": pending["title"],
				"desc": pending["desc"],
				"icon": pending["icon"],
				"pri": pending["pri"],
				"dur": max(dur, 0.0),
				"clip": pending["clip"],
				"handle": handle,
			}
		if evt_type == "UpdateRangeTimelineEvent":
			handle = data.get("handle", 0)
			with self._lock:
				p = self._pending_ranges.get(handle)
				if p:
					p.update({
						"title": data.get("title", p["title"]),
						"desc": data.get("description", p["desc"]),
						"icon": data.get("icon", p["icon"]),
						"pri": data.get("priority", p["pri"]),
						"clip": data.get("clipPriority", p["clip"]),
					})
			return None
		if evt_type == "RemoveTimelineEvent":
			handle = data.get("handle", 0)
			with self._lock:
				self.events = [e for e in self.events if e.get("handle") != handle]
				self._pending_ranges.pop(handle, None)
			return None
		if evt_type == "SetTimelineTooltip":
			return {
				"type": "tooltip",
				"t": now,
				"text": data.get("description", ""),
				"timeDelta": data.get("timeDelta", 0.0),
			}
		if evt_type == "ClearTimelineTooltip":
			return {"type": "tooltip_clear", "t": now}
		if evt_type == "SetTimelineGameMode":
			return {"type": "gamemode", "t": now, "mode": data.get("mode", 0)}
		if evt_type == "StartGamePhase":
			return {"type": "phase_start", "t": now}
		if evt_type == "EndGamePhase":
			return {"type": "phase_end", "t": now}
		if evt_type == "SetGamePhaseID":
			return {"type": "phase_id", "t": now, "phaseID": data.get("phaseID", "")}
		if evt_type == "AddGamePhaseTag":
			return {
				"type": "phase_tag",
				"t": now,
				"tagName": data.get("tagName", ""),
				"tagIcon": data.get("tagIcon", ""),
				"tagGroup": data.get("tagGroup", ""),
				"pri": data.get("priority", 0),
			}
		if evt_type == "SetGamePhaseAttribute":
			return {
				"type": "phase_attr",
				"t": now,
				"group": data.get("attributeGroup", ""),
				"value": data.get("attributeValue", ""),
				"pri": data.get("priority", 0),
			}
		if evt_type == "OpenOverlayToGamePhase":
			return {"type": "overlay_phase", "t": now, "phaseID": data.get("phaseID", "")}
		if evt_type == "OpenOverlayToTimelineEvent":
			return {"type": "overlay_event", "t": now, "handle": data.get("handle", 0)}
		return None


G = State()


def script_load(settings):
	obs.obs_frontend_add_event_callback(_on_frontend_event)
	G.pipe_start()


def script_unload():
	obs.obs_frontend_remove_event_callback(_on_frontend_event)
	G.pipe_stop()


def script_defaults(settings):
	obs.obs_data_set_default_string(settings, "output_dir", "")
	obs.obs_data_set_default_double(settings, "replay_duration", 120.0)
	obs.obs_data_set_default_string(settings, "ffmpeg_path", "ffmpeg")
	obs.obs_data_set_default_double(settings, "delay", 2.0)


def script_update(settings):
	G.output_dir = obs.obs_data_get_string(settings, "output_dir")
	G.replay_duration = obs.obs_data_get_double(settings, "replay_duration")
	fp = obs.obs_data_get_string(settings, "ffmpeg_path")
	G.ffmpeg_path = fp if fp else "ffmpeg"
	G.delay = obs.obs_data_get_double(settings, "delay")


def script_properties():
	props = obs.obs_properties_create()
	obs.obs_properties_add_path(
		props,
		"output_dir",
		"OBS recordings folder",
		obs.OBS_PATH_DIRECTORY,
		None,
		None,
	)
	obs.obs_properties_add_float_slider(
		props,
		"replay_duration",
		"Replay buffer duration (s)",
		10,
		600,
		1,
	)
	obs.obs_properties_add_text(
		props,
		"ffmpeg_path",
		"FFmpeg path",
		obs.OBS_TEXT_DEFAULT,
	)
	obs.obs_properties_add_float_slider(
		props,
		"delay",
		"Embed delay (s) — wait before running FFmpeg",
		0,
		30,
		0.5,
	)
	return props


def script_description():
	return (
		"<h3>Steam Timeline Metadata</h3>"
		"<p>Receives Steam Timeline events from the <b>iClientTimeline hook</b> "
		f"via the named pipe <code>{PIPE_NAME}</code> and embeds them "
		"as timed metadata into OBS recordings and replay buffer saves.</p>"
		"<p><b>Output dir</b> - where OBS saves recordings "
		"(needed for RecOrganizer compatibility)</p>"
		"<p><b>FFmpeg path</b> - path to ffmpeg "
		"(default: <code>ffmpeg</code> from PATH)</p>"
		"<p><b>Embed delay</b> - seconds to wait before FFmpeg runs.</p>"
	)


def script_tick(seconds):
	G._tick_acc += seconds
	if G._tick_acc < 5.0:
		return
	G._tick_acc = 0.0
	now = time.time()
	cutoff = now - max(G.replay_duration, 3600)
	with G._lock:
		G.events = [e for e in G.events if e["t"] >= cutoff]


def _on_frontend_event(event):
	if event == obs.OBS_FRONTEND_EVENT_RECORDING_STARTED:
		G._recording_start_t = time.time()
	elif event == obs.OBS_FRONTEND_EVENT_RECORDING_STOPPED:
		_handle_save(recording=True)
	elif event == obs.OBS_FRONTEND_EVENT_REPLAY_BUFFER_SAVED:
		_handle_save(recording=False)


def _handle_save(recording):
	ptr = obs.obs_frontend_get_last_recording() if recording else obs.obs_frontend_get_last_replay()
	if not ptr:
		return
	threading.Thread(target=_embed_thread, args=(recording, os.path.normpath(ptr)), daemon=True).start()


def _find_moved_file(original, output_dir, timeout=10):
	if not output_dir:
		return _wait_for_file(original, timeout) or original
	deadline = time.time() + timeout
	name = os.path.basename(original)
	while time.time() < deadline:
		if os.path.isfile(original):
			return original
		found = _search_dir(output_dir, name)
		if found:
			return found
		time.sleep(0.5)
	return _wait_for_file(original, 1) or _search_dir(output_dir, name)


def _wait_for_file(path, timeout):
	deadline = time.time() + timeout
	while time.time() < deadline:
		if os.path.isfile(path):
			return path
		time.sleep(0.2)
	return path if os.path.isfile(path) else None


def _search_dir(root, filename):
	try:
		for entry in os.scandir(root):
			if entry.is_dir():
				found = _search_dir(entry.path, filename)
				if found:
					return found
			elif entry.name == filename:
				return entry.path
	except OSError:
		pass
	return None


def _embed_thread(recording, orig_path):
	time.sleep(max(G.delay, 0.5))
	video = _find_moved_file(orig_path, G.output_dir)
	if not video or not os.path.isfile(video):
		print(f"[SteamTimeline] Could not find video: {orig_path}")
		return
	with G._lock:
		now = time.time()
		start_t = (G._recording_start_t or 0) if recording else (now - G.replay_duration)
		evts_raw = [e for e in G.events if start_t <= e["t"] <= now]
		if not evts_raw:
			total = len(G.events)
			oldest = G.events[0]["t"] if G.events else 0
			newest = G.events[-1]["t"] if G.events else 0
			print(f"[SteamTimeline] No events in window [{now - start_t:.0f}s ago .. now]. Have {total} events spanning {newest - oldest:.0f}s.")
			return
		rel_evts = [{**e, "t": round(e["t"] - start_t, 3)} for e in evts_raw]
		kind = "recording" if recording else "replay"
		print(f"[SteamTimeline] Embedding {len(rel_evts)} events into {kind} ({os.path.basename(video)})")
	try:
		j = json.dumps(rel_evts, separators=(",", ":"))
	except Exception:
		return
	tmp = os.path.splitext(video)[0] + ".meta_tmp" + os.path.splitext(video)[1]
	creation_flags = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0
	try:
		result = subprocess.run(
			[
				G.ffmpeg_path,
				"-y",
				"-i",
				video,
				"-map",
				"0",
				"-c",
				"copy",
				"-movflags",
				"use_metadata_tags",
				"-metadata",
				f"comment={j}",
				tmp,
			],
			capture_output=True,
			text=True,
			timeout=120,
			creationflags=creation_flags,
		)
		if result.returncode == 0:
			try:
				os.replace(tmp, video)
				print(f"[SteamTimeline] Metadata embedded in {os.path.basename(video)}")
			except OSError:
				os.remove(tmp)
				print("[SteamTimeline] Could not replace original file with temp")
		else:
			print(f"[SteamTimeline] FFmpeg failed:\n{result.stderr.strip()}")
			try:
				os.remove(tmp)
			except OSError:
				pass
	except FileNotFoundError:
		print(f"[SteamTimeline] FFmpeg not found at '{G.ffmpeg_path}'. Set path in script settings or ensure ffmpeg is in PATH.")
	except subprocess.TimeoutExpired:
		print("[SteamTimeline] FFmpeg timed out")
		try:
			os.remove(tmp)
		except OSError:
			pass
	except Exception as e:
		print(f"[SteamTimeline] Error: {e}")
		try:
			os.remove(tmp)
		except OSError:
			pass
