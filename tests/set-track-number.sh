#!/usr/bin/env bash
set -euo pipefail

# End-to-end regression coverage for non-recursive Track metadata assignment.
usage() {
	cat <<'HELP'
Usage: tests/set-track-number.sh

Create temporary audio fixtures and verify set-track-number ordering, format
support, dry-run behavior, validation, and preservation of audio streams.
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

track_value() {
	ffprobe -v error -show_entries format_tags=track:stream_tags=track \
		-of default=nw=1:nk=1 "$1" | sed -n '/./{p;q;}'
}

audio_hash() {
	ffmpeg -v error -nostdin -i "$1" -map 0:a:0 -c copy -f data - | sha256sum | awk '{print $1}'
}

workspace="$test_root/Track Workspace"
book="$workspace/Book Files"
mkdir -p "$book/Nested"
printf 'version=1\n' >"$workspace/.audiobook-workspace"

# Exercise every supported extension and each container-specific metadata path.
ffmpeg -v error -f lavfi -i 'sine=frequency=401:duration=0.1' -q:a 9 -metadata title=Keep -metadata track=99 "$book/01 track.mp3"
ffmpeg -v error -f lavfi -i 'sine=frequency=402:duration=0.1' -c:a aac -f adts "$book/02.aac"
ffmpeg -v error -f lavfi -i 'sine=frequency=403:duration=0.1' -c:a alac -f caf "$book/03.alac"
ffmpeg -v error -f lavfi -i 'sine=frequency=404:duration=0.1' -c:a flac "$book/04.flac"
ffmpeg -v error -f lavfi -i 'sine=frequency=405:duration=0.1' -c:a aac "$book/05.m4a"
ffmpeg -v error -f lavfi -i 'sine=frequency=406:duration=0.1' -c:a aac -f ipod "$book/06.m4b"
ffmpeg -v error -f lavfi -i 'sine=frequency=407:duration=0.1' -c:a libvorbis "$book/07.oga"
ffmpeg -v error -f lavfi -i 'sine=frequency=408:duration=0.1' -c:a libvorbis "$book/08.ogg"
ffmpeg -v error -f lavfi -i 'sine=frequency=409:duration=0.1' -c:a libopus "$book/09.opus"
ffmpeg -v error -f lavfi -i 'sine=frequency=410:duration=0.1' "$book/10.wav"
ffmpeg -v error -f lavfi -i 'sine=frequency=411:duration=0.1' -c:a wmav2 "$book/11.wma"
ffmpeg -v error -f lavfi -i 'sine=frequency=499:duration=0.1' -q:a 9 -metadata track=77 "$book/Nested/01.mp3"
printf 'notes\n' >"$book/notes.txt"

declare -A before_hashes=()
while IFS= read -r -d '' file; do
	before_hashes["$file"]="$(audio_hash "$file")"
done < <(find "$book" -maxdepth 1 -type f ! -name notes.txt -print0)
nested_hash="$(sha256sum "$book/Nested/01.mp3" | awk '{print $1}')"

# Dry-run reports natural assignments and changes no metadata or file content.
(cd "$workspace" && "$command_path" set-track-number --dry-run "$book") >"$test_root/dry-run-output"
require_output "would set Track 1: $book/01 track.mp3" "$test_root/dry-run-output"
require_output "would set Track 11: $book/11.wma" "$test_root/dry-run-output"
require_output 'planned Track updates for 11 files' "$test_root/dry-run-output"
[[ "$(track_value "$book/01 track.mp3")" == 99 ]] || { echo 'dry-run changed Track metadata' >&2; exit 1; }

(cd "$workspace" && "$command_path" set-track-number "$book") >"$test_root/update-output"
require_output 'updated Track metadata for 11 files' "$test_root/update-output"

index=1
while IFS= read -r -d '' file; do
	[[ "$(track_value "$file")" == "$index" ]] || {
		echo "unexpected Track value for $file" >&2
		exit 1
	}
	[[ "$(audio_hash "$file")" == "${before_hashes[$file]}" ]] || {
		echo "audio stream changed for $file" >&2
		exit 1
	}
	((index += 1))
done < <(find "$book" -maxdepth 1 -type f ! -name notes.txt -print0 | sort -zV)

[[ "$(ffprobe -v error -show_entries format_tags=title -of default=nw=1:nk=1 "$book/01 track.mp3")" == Keep ]] || {
	echo 'existing metadata was not preserved' >&2
	exit 1
}
[[ "$(sha256sum "$book/Nested/01.mp3" | awk '{print $1}')" == "$nested_hash" ]] || {
	echo 'nested audio file was changed' >&2
	exit 1
}
if find "$book" -name '.set-track-number.*' -print -quit | grep -q .; then
	echo 'temporary files were not removed' >&2
	exit 1
fi

empty_dir="$workspace/Empty"
mkdir "$empty_dir"
set +e
(cd "$workspace" && "$command_path" set-track-number "$empty_dir") >"$test_root/empty-output" 2>"$test_root/empty-error"
empty_status=$?
(cd "$workspace" && "$command_path" set-track-number) >"$test_root/missing-output" 2>"$test_root/missing-error"
missing_status=$?
"$command_path" set-track-number "$book" >"$test_root/outside-output" 2>"$test_root/outside-error"
outside_status=$?
set -e

[[ "$empty_status" == 1 ]] || { echo "expected empty-directory status 1, got $empty_status" >&2; exit 1; }
[[ "$missing_status" == 2 ]] || { echo "expected missing-directory status 2, got $missing_status" >&2; exit 1; }
[[ "$outside_status" == 1 ]] || { echo "expected outside-workspace status 1, got $outside_status" >&2; exit 1; }
require_output 'no supported audio files found directly' "$test_root/empty-error"
require_output 'DIRECTORY is required' "$test_root/missing-error"
require_output 'run this command inside an audiobook-convert workspace' "$test_root/outside-error"

echo 'set-track-number regression tests passed'
