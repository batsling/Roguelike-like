extends RefCounted

# What a music file says about itself: title, artist, album and year, read out of
# its own tags. Used by the Radio's song-list export (`Radio.export_library`),
# which hands `tools/apply_radio_import.py` everything it needs to write the
# `radio` sheet's rows without the music ever leaving the player's PC
# (docs/roguelike-radio.md §2a).
#
# Godot plays these formats but exposes none of their tags, so this reads them
# itself, one format each:
#
#   .mp3  ID3v2 (2.2, 2.3, 2.4) at the front, ID3v1 at the back as a fallback
#   .ogg  the Vorbis (or Opus) comment packet, reassembled from Ogg pages
#   .wav  the RIFF `LIST INFO` chunk
#
# It never reads a whole file: frames it doesn't want (cover art, which can be
# megabytes) are seeked past. Anything it can't read comes back blank, and the
# importer falls back to the file name. No class_name, so it needs no editor
# rescan: preload it.

const KEYS := ["title", "artist", "album", "year"]
# Frames past this are not tags anyone wrote by hand; a corrupt size field is the
# usual reason to see one, and following it would read the whole file.
const MAX_FRAME := 1 << 20
# Cover art rides in the comment packet, a few hundred 4 KB pages of it.
const MAX_OGG_PAGES := 8192

static func read(path: String) -> Dictionary:
	var out := {"title": "", "artist": "", "album": "", "year": ""}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var ext: String = path.get_extension().to_lower()
	if ext == "mp3":
		_read_id3v2(f, out)
		if out["title"] == "" or out["artist"] == "":
			_read_id3v1(f, out)
	elif ext == "ogg":
		_read_ogg(f, out)
	elif ext == "wav":
		_read_wav(f, out)
	f.close()
	for k in KEYS:
		out[k] = String(out[k]).strip_edges()
	out["year"] = _year(out["year"])
	return out

# The first four-digit run in a date ("2020-05-01", "2020", "c. 2020").
static func _year(s: String) -> String:
	var re := RegEx.new()
	re.compile("\\d{4}")
	var m := re.search(s)
	return m.get_string() if m != null else ""

static func _fill(out: Dictionary, key: String, value: String) -> void:
	if out[key] == "" and value.strip_edges() != "":
		out[key] = value

# --- ID3v2 ---------------------------------------------------------------------

const ID3_FRAMES := {
	"TIT2": "title", "TPE1": "artist", "TALB": "album", "TYER": "year", "TDRC": "year",
	"TPE2": "album_artist", "TT2": "title", "TP1": "artist", "TAL": "album", "TYE": "year",
	"TP2": "album_artist",
}

static func _read_id3v2(f: FileAccess, out: Dictionary) -> void:
	f.seek(0)
	var head: PackedByteArray = f.get_buffer(10)
	if head.size() < 10 or head.slice(0, 3).get_string_from_ascii() != "ID3":
		return
	var major: int = head[3]
	var flags: int = head[5]
	var tag_size: int = _syncsafe(head, 6)
	var end: int = 10 + tag_size
	var whole_unsync: bool = (flags & 0x80) != 0 and major < 4
	var pos: int = 10
	if (flags & 0x40) != 0 and major >= 3:
		f.seek(10)
		var ext: PackedByteArray = f.get_buffer(4)
		pos += _syncsafe(ext, 0) if major == 4 else 4 + _be32(ext, 0)
	var album_artist: String = ""
	var id_len: int = 3 if major == 2 else 4
	var head_len: int = 6 if major == 2 else 10
	while pos + head_len <= end:
		f.seek(pos)
		var fh: PackedByteArray = f.get_buffer(head_len)
		if fh.size() < head_len or fh[0] == 0:
			break  # padding
		var fid: String = fh.slice(0, id_len).get_string_from_ascii()
		var size: int
		var fflags: int = 0
		if major == 2:
			size = (fh[3] << 16) | (fh[4] << 8) | fh[5]
		elif major == 4:
			size = _syncsafe(fh, 4)
			fflags = fh[9]
		else:
			size = _be32(fh, 4)
		pos += head_len
		if size <= 0 or pos + size > end + 1:
			break
		var key: String = ID3_FRAMES.get(fid, "")
		var skip: bool = key == "" or size > MAX_FRAME
		# 2.4 per-frame flags: compressed or encrypted frames are left alone.
		if major == 4 and (fflags & 0x0C) != 0:
			skip = true
		if not skip:
			var body: PackedByteArray = f.get_buffer(size)
			if major == 4 and (fflags & 0x01) != 0:
				body = body.slice(4)  # data length indicator
			if whole_unsync or (major == 4 and (fflags & 0x02) != 0):
				body = _unsync(body)
			var text: String = _id3_text(body)
			if key == "album_artist":
				album_artist = text
			else:
				_fill(out, key, text)
		pos += size
	_fill(out, "artist", album_artist)

static func _syncsafe(b: PackedByteArray, at: int) -> int:
	return ((b[at] & 0x7f) << 21) | ((b[at + 1] & 0x7f) << 14) | ((b[at + 2] & 0x7f) << 7) | (b[at + 3] & 0x7f)

static func _be32(b: PackedByteArray, at: int) -> int:
	return (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3]

static func _le32(b: PackedByteArray, at: int) -> int:
	return b[at] | (b[at + 1] << 8) | (b[at + 2] << 16) | (b[at + 3] << 24)

# Undo ID3 unsynchronisation: every 0xFF 0x00 was written for a 0xFF.
static func _unsync(b: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	var i: int = 0
	while i < b.size():
		out.append(b[i])
		if b[i] == 0xFF and i + 1 < b.size() and b[i + 1] == 0x00:
			i += 1
		i += 1
	return out

# A text frame: one encoding byte, then the text. 2.4 can hold several values
# split by NULs; the first is the one shown everywhere, so that is the one kept.
static func _id3_text(body: PackedByteArray) -> String:
	if body.is_empty():
		return ""
	var enc: int = body[0]
	var data: PackedByteArray = body.slice(1)
	match enc:
		1:
			return _utf16(data, false)
		2:
			return _utf16(data, true)
		3:
			return _utf8(data)
		_:
			return _latin1(data)

# Each decoder stops at the first NUL: a 2.4 frame's later values, and the
# padding a fixed-width field is filled with, are not part of the text.
static func _utf8(b: PackedByteArray) -> String:
	var cut: int = b.find(0)
	return (b.slice(0, cut) if cut >= 0 else b).get_string_from_utf8()

static func _latin1(b: PackedByteArray) -> String:
	var s: String = ""
	for byte in b:
		if byte == 0:
			break
		s += char(byte)
	return s

# UTF-16 decoded by hand: the BOM decides the byte order (big-endian when there
# isn't one and the frame says so), and a pair of surrogates makes one character.
static func _utf16(b: PackedByteArray, big_endian: bool) -> String:
	var i: int = 0
	if b.size() >= 2:
		if b[0] == 0xFF and b[1] == 0xFE:
			big_endian = false
			i = 2
		elif b[0] == 0xFE and b[1] == 0xFF:
			big_endian = true
			i = 2
	var s: String = ""
	var high: int = 0
	while i + 1 < b.size():
		var u: int = (b[i] << 8) | b[i + 1] if big_endian else b[i] | (b[i + 1] << 8)
		i += 2
		if u == 0:
			break
		if u >= 0xD800 and u <= 0xDBFF:
			high = u
			continue
		if u >= 0xDC00 and u <= 0xDFFF and high != 0:
			s += char(0x10000 + ((high - 0xD800) << 10) + (u - 0xDC00))
			high = 0
			continue
		high = 0
		s += char(u)
	return s

# --- ID3v1 ---------------------------------------------------------------------

static func _read_id3v1(f: FileAccess, out: Dictionary) -> void:
	if f.get_length() < 128:
		return
	f.seek(f.get_length() - 128)
	var b: PackedByteArray = f.get_buffer(128)
	if b.slice(0, 3).get_string_from_ascii() != "TAG":
		return
	_fill(out, "title", _latin1(b.slice(3, 33)))
	_fill(out, "artist", _latin1(b.slice(33, 63)))
	_fill(out, "album", _latin1(b.slice(63, 93)))
	_fill(out, "year", _latin1(b.slice(93, 97)))

# --- Ogg Vorbis / Opus -----------------------------------------------------------

# The comment header is the stream's SECOND packet. A packet can span pages (it
# does whenever cover art is embedded), so pages are walked and their segments
# joined until that packet ends, rather than searching the bytes for "vorbis".
static func _read_ogg(f: FileAccess, out: Dictionary) -> void:
	f.seek(0)
	var packet := PackedByteArray()
	var packets_done: int = 0
	var pages: int = 0
	while pages < MAX_OGG_PAGES and f.get_position() + 27 <= f.get_length():
		var head: PackedByteArray = f.get_buffer(27)
		if head.slice(0, 4).get_string_from_ascii() != "OggS":
			return
		pages += 1
		var lacing: PackedByteArray = f.get_buffer(head[26])
		for seg in lacing:
			var data: PackedByteArray = f.get_buffer(seg)
			if packets_done == 1:
				if packet.size() + seg > MAX_FRAME * 16:
					return
				packet.append_array(data)
			if seg < 255:
				packets_done += 1
				if packets_done == 2:
					_vorbis_comments(packet, out)
					return

static func _vorbis_comments(p: PackedByteArray, out: Dictionary) -> void:
	var at: int
	if p.size() >= 7 and p[0] == 3 and p.slice(1, 7).get_string_from_ascii() == "vorbis":
		at = 7
	elif p.size() >= 8 and p.slice(0, 8).get_string_from_ascii() == "OpusTags":
		at = 8
	else:
		return
	if at + 4 > p.size():
		return
	at += 4 + _le32(p, at)  # vendor string
	if at + 4 > p.size():
		return
	var count: int = _le32(p, at)
	at += 4
	var album_artist: String = ""
	for _i in count:
		if at + 4 > p.size():
			break
		var n: int = _le32(p, at)
		at += 4
		if n < 0 or at + n > p.size():
			break
		var entry: String = _utf8(p.slice(at, at + n))
		at += n
		var eq: int = entry.find("=")
		if eq <= 0:
			continue
		var value: String = entry.substr(eq + 1)
		match entry.substr(0, eq).to_upper():
			"TITLE":
				_fill(out, "title", value)
			"ARTIST":
				_fill(out, "artist", value)
			"ALBUM":
				_fill(out, "album", value)
			"DATE", "YEAR":
				_fill(out, "year", value)
			"ALBUMARTIST", "ALBUM ARTIST":
				album_artist = value
	_fill(out, "artist", album_artist)

# --- WAV --------------------------------------------------------------------------

const RIFF_INFO := {"INAM": "title", "IART": "artist", "IPRD": "album", "ICRD": "year"}

static func _read_wav(f: FileAccess, out: Dictionary) -> void:
	f.seek(0)
	var head: PackedByteArray = f.get_buffer(12)
	if head.size() < 12 or head.slice(0, 4).get_string_from_ascii() != "RIFF" \
			or head.slice(8, 12).get_string_from_ascii() != "WAVE":
		return
	var pos: int = 12
	while pos + 8 <= f.get_length():
		f.seek(pos)
		var ch: PackedByteArray = f.get_buffer(8)
		var cid: String = ch.slice(0, 4).get_string_from_ascii()
		var size: int = _le32(ch, 4)
		if size < 0:
			return
		if cid == "LIST" and size >= 4 and size <= MAX_FRAME:
			var body: PackedByteArray = f.get_buffer(size)
			if body.slice(0, 4).get_string_from_ascii() == "INFO":
				var at: int = 4
				while at + 8 <= body.size():
					var sid: String = body.slice(at, at + 4).get_string_from_ascii()
					var n: int = _le32(body, at + 4)
					var key: String = RIFF_INFO.get(sid, "")
					if key != "":
						_fill(out, key, _utf8(body.slice(at + 8, at + 8 + n)))
					at += 8 + n + (n & 1)
		pos += 8 + size + (size & 1)
