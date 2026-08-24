#!/usr/bin/env bash
set -euo pipefail

# End-to-end regression coverage for the read-only audiobook inspection command.
usage() {
	cat <<'HELP'
Usage: tests/inspect.sh

Create temporary audio fixtures and verify audiobook-convert inspect output,
exit statuses, diagnostics, and source immutability.
HELP
}

if (($# > 0)); then
	case "$1" in
	-h | --help)
		usage
		exit 0
		;;
	*)
		echo "error: this test accepts no arguments" >&2
		usage >&2
		exit 2
		;;
	esac
fi

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
command_path="$project_dir/audiobook-convert"
test_root="$(mktemp -d)"
trap 'rm -rf --one-file-system -- "$test_root"' EXIT

require_output() {
	local pattern="$1"
	local file="$2"
	if ! grep -F -- "$pattern" "$file" >/dev/null; then
		echo "missing expected output: $pattern" >&2
		sed -n '1,240p' "$file" >&2
		exit 1
	fi
}
reject_output() {
	local pattern="$1"
	local file="$2"
	if grep -F -- "$pattern" "$file" >/dev/null; then
		echo "unexpected output: $pattern" >&2
		sed -n '1,240p' "$file" >&2
		exit 1
	fi
}
require_pattern() {
	local pattern="$1"
	local file="$2"
	if ! grep -E -- "$pattern" "$file" >/dev/null; then
		echo "missing expected pattern: $pattern" >&2
		sed -n '1,240p' "$file" >&2
		exit 1
	fi
}

create_mp3() {
	local output="$1"
	local track="$2"
	local title="$3"
	mkdir -p "$(dirname -- "$output")"
	ffmpeg -v error -f lavfi -i 'sine=frequency=440:duration=0.1' \
		-metadata "track=$track" -metadata "title=$title" \
		-metadata 'album=Inspection Test' -metadata 'artist=Test Author' \
		-id3v2_version 3 -write_id3v1 1 -q:a 9 "$output"
}

real_jq="$(command -v jq)"
real_iconv="$(command -v iconv)"
real_mediainfo="$(command -v mediainfo)"
real_exiftool="$(command -v exiftool)"
trace_bin="$test_root/trace-bin"
trace_file="$test_root/tool-trace"
mkdir -p "$trace_bin"
printf '%s\n' '#!/usr/bin/env bash' 'printf "jq\n" >>"$INSPECT_TOOL_TRACE"' 'exec "$INSPECT_REAL_JQ" "$@"' >"$trace_bin/jq"
printf '%s\n' '#!/usr/bin/env bash' 'printf "iconv\n" >>"$INSPECT_TOOL_TRACE"' 'exec "$INSPECT_REAL_ICONV" "$@"' >"$trace_bin/iconv"
printf '%s\n' '#!/usr/bin/env bash' 'printf "exiftool\n" >>"$INSPECT_TOOL_TRACE"' 'exec "$INSPECT_REAL_EXIFTOOL" "$@"' >"$trace_bin/exiftool"
printf '%s\n' '#!/usr/bin/env bash' 'printf "mediainfo\n" >>"$INSPECT_TOOL_TRACE"' 'exec "$INSPECT_REAL_MEDIAINFO" "$@"' >"$trace_bin/mediainfo"
chmod +x "$trace_bin/jq" "$trace_bin/iconv" "$trace_bin/mediainfo" "$trace_bin/exiftool"

clean_book="$test_root/Clean Book"
create_mp3 "$clean_book/Part 1/01.mp3" 1 'First Chapter'
create_mp3 "$clean_book/Part 1/02.mp3" 2 'Second Chapter'
create_mp3 "$clean_book/Part 1/Bonus/03.mp3" 3 'Bonus Chapter'
mkdir -p "$clean_book/Part 1/Обложка"
ffmpeg -v error -f lavfi -i 'color=c=blue:s=600x600:d=0.1' -frames:v 1 \
	"$clean_book/Part 1/Обложка/cover.jpg"
printf '%s\n' 'book notes' >"$clean_book/notes.txt"
before_hash="$(sha256sum "$clean_book/Part 1/01.mp3")"
INSPECT_REAL_JQ="$real_jq" INSPECT_REAL_ICONV="$real_iconv" INSPECT_REAL_MEDIAINFO="$real_mediainfo" INSPECT_REAL_EXIFTOOL="$real_exiftool" INSPECT_TOOL_TRACE="$trace_file" \
	PATH="$trace_bin:$PATH" "$command_path" inspect "$clean_book" >"$test_root/clean-report"
jq_calls="$(grep -c '^jq$' "$trace_file")"
iconv_calls="$(grep -c '^iconv$' "$trace_file")"
mediainfo_calls="$(grep -c '^mediainfo$' "$trace_file")"
exiftool_calls="$(grep -c '^exiftool$' "$trace_file")"
[[ "$jq_calls" == 4 ]] || { echo "expected one jq call per file plus tag parsing, got $jq_calls" >&2; exit 1; }
[[ "$iconv_calls" == 3 ]] || { echo "expected only path UTF-8 checks, got $iconv_calls iconv calls" >&2; exit 1; }
[[ "$mediainfo_calls" == 3 ]] || { echo "expected one MediaInfo call per file, got $mediainfo_calls" >&2; exit 1; }
[[ "$exiftool_calls" == 1 ]] || { echo "expected one ExifTool call per inspection, got $exiftool_calls" >&2; exit 1; }

after_hash="$(sha256sum "$clean_book/Part 1/01.mp3")"
[[ "$before_hash" == "$after_hash" ]] || {
	echo "inspect changed a source audio file" >&2
	exit 1
}
require_output 'Location:  original source' "$test_root/clean-report"
require_output 'Audio tree' "$test_root/clean-report"
require_pattern '└── Part 1/ +0:00:00' "$test_root/clean-report"
require_output '    ├── 01.mp3' "$test_root/clean-report"
require_output '    ├── 02.mp3' "$test_root/clean-report"
require_pattern '    └── Bonus/ +0:00:00' "$test_root/clean-report"
require_output '        └── 03.mp3' "$test_root/clean-report"
require_output 'First Chapter' "$test_root/clean-report"
require_output 'ID3v2.3 + ID3v1' "$test_root/clean-report"
require_output 'Images' "$test_root/clean-report"
require_output 'Part 1/Обложка/cover.jpg' "$test_root/clean-report"
require_output '600x600' "$test_root/clean-report"
reject_output 'ROLE' "$test_root/clean-report"
reject_output 'likely cover' "$test_root/clean-report"
require_output 'Other files' "$test_root/clean-report"
require_output 'notes.txt' "$test_root/clean-report"
cover_mentions="$(grep -Fc 'cover.jpg' "$test_root/clean-report")"
[[ "$cover_mentions" == 1 ]] || { echo "expected cover image outside Other files" >&2; exit 1; }
require_output 'ISSUES' "$test_root/clean-report"
reject_output '[3 files' "$test_root/clean-report"
reject_output '[1 file' "$test_root/clean-report"
reject_output 'Structure' "$test_root/clean-report"
reject_output 'Audio files' "$test_root/clean-report"
require_output 'KiB' "$test_root/clean-report"
require_output 'WARNING: no embedded cover artwork was found' "$test_root/clean-report"
require_output 'Summary: 0 error(s), 1 warning(s)' "$test_root/clean-report"

format_book="$test_root/Format Book"
asset_dir="$test_root/format-assets"
mkdir -p "$format_book/MP3" "$format_book/FLAC" "$format_book/M4A" "$asset_dir"
create_mp3 "$asset_dir/source.mp3" '2/10' 'MP3 Covered'
ffmpeg -v error -f lavfi -i 'sine=frequency=550:duration=0.1' \
	-metadata track='2/10' -metadata title='FLAC Covered' \
	-metadata album='Format Test' -metadata artist='Format Author' \
	-metadata album_artist='Format Album Artist' "$asset_dir/source.flac"
ffmpeg -v error -f lavfi -i 'sine=frequency=660:duration=0.1' \
	-metadata track='2/10' -metadata title='M4A Covered' \
	-metadata album='Format Test' -metadata artist='Format Author' \
	-metadata album_artist='Format Album Artist' -c:a aac "$asset_dir/source.m4a"
ffmpeg -v error -f lavfi -i 'color=c=blue:s=32x32:d=0.1' -frames:v 1 "$asset_dir/cover.jpg"
ffmpeg -v error -f lavfi -i 'color=c=green:s=32x32:d=0.1' -frames:v 1 "$asset_dir/cover.png"
ffmpeg -v error -i "$asset_dir/source.mp3" -i "$asset_dir/cover.jpg" \
	-map 0:a -map 1:v -c copy -id3v2_version 3 -metadata:s:v comment='Cover (front)' \
	"$format_book/MP3/02.mp3"
ffmpeg -v error -i "$asset_dir/source.flac" -i "$asset_dir/cover.png" \
	-map 0:a -map 1:v -c copy -disposition:v attached_pic "$format_book/FLAC/02.flac"
ffmpeg -v error -i "$asset_dir/source.m4a" -i "$asset_dir/cover.jpg" \
	-map 0:a -map 1:v -c copy -disposition:v attached_pic "$format_book/M4A/02.m4a"
set +e
"$command_path" inspect "$format_book" >"$test_root/format-report"
format_status=$?
set -e
[[ "$format_status" == 1 ]] || { echo "expected non-MP3 chapter blockers, got $format_status" >&2; exit 1; }
require_output 'Artwork:   3 of 3 audio files' "$test_root/format-report"
require_output '2/10' "$test_root/format-report"
require_output 'MP3 Covered' "$test_root/format-report"
require_output 'FLAC Covered' "$test_root/format-report"
require_output 'M4A Covered' "$test_root/format-report"
require_output 'Vorbis' "$test_root/format-report"
require_output 'MP4' "$test_root/format-report"
problem_book="$test_root/Problem Book"
create_mp3 "$problem_book/01.mp3" 1 'Ñòóäèÿ ÀÐÄÈÑ ïðåäñòàâëÿåò'
create_mp3 "$problem_book/02.mp3" 1 'Duplicate Track'
printf '%s\n' 'not audio' >"$problem_book/04.mp3"
ffmpeg -v error -f lavfi -i 'sine=frequency=770:duration=0.1' -q:a 9 "$problem_book/05.mp3"
create_mp3 "$problem_book/06.mp3" 'side-a' 'Nonnumeric Track'
create_mp3 "$problem_book/07.mp3" 2 'Out of Order'
printf '%s\n' '<Tags><broken></Tags>' >"$problem_book/tags.xml"
printf '%s\n' 'not chapter data' >"$problem_book/chapters.txt"
ffmpeg -v error -f lavfi -i 'sine=frequency=660:duration=0.1' \
	-metadata track=3 -metadata title='Non MP3 Chapter' "$problem_book/03.flac"
set +e
"$command_path" inspect "$problem_book" >"$test_root/problem-report"
problem_status=$?
set -e
[[ "$problem_status" == 1 ]] || {
	echo "expected blocker report to exit 1, got $problem_status" >&2
	exit 1
}
require_output 'tags.xml: malformed XML' "$test_root/problem-report"
require_output 'chapters.txt: malformed simple chapter data' "$test_root/problem-report"
require_output 'E:duplicate Track' "$test_root/problem-report"
require_output 'E:unreadable audio' "$test_root/problem-report"
require_pattern '04\.mp3 +none +\?' "$test_root/problem-report"
require_output 'E:missing Track; E:missing Title' "$test_root/problem-report"
require_output 'W:CP1251 mojibake' "$test_root/problem-report"
require_output 'W:Track gap' "$test_root/problem-report"
require_output 'W:nonnumeric Track' "$test_root/problem-report"
require_output 'W:Track out of order' "$test_root/problem-report"
require_output 'ERROR (1 file): duplicate Track in one directory' "$test_root/problem-report"
require_output 'ERROR (1 file): missing Track tag' "$test_root/problem-report"
require_output 'ERROR (1 file): missing MP3 Title tag' "$test_root/problem-report"
require_output 'ERROR (1 file): unreadable or unrecognized audio' "$test_root/problem-report"
require_output 'WARNING (1 file): CP1251 mojibake' "$test_root/problem-report"
require_output 'non-MP3 audio file(s) will be omitted' "$test_root/problem-report"

empty_book="$test_root/Empty Book"
mkdir -p "$empty_book"
set +e
"$command_path" inspect "$empty_book" >"$test_root/empty-report" 2>"$test_root/empty-error"
empty_status=$?
set -e
[[ "$empty_status" == 1 ]] || {
	echo "expected empty source to exit 1, got $empty_status" >&2
	exit 1
}
require_output 'no supported audio files found' "$test_root/empty-error"

set +e
"$command_path" inspect --unknown >"$test_root/usage-output" 2>"$test_root/usage-error"
usage_status=$?
set -e
[[ "$usage_status" == 2 ]] || {
	echo "expected invalid usage to exit 2, got $usage_status" >&2
	exit 1
}

echo "inspect regression tests passed"
