#!/usr/bin/env bash
set -euo pipefail

# End-to-end coverage for lossless, destructive audio concatenation.
usage() {
	cat <<'HELP'
Usage: tests/combine-audio.sh

Create temporary audio fixtures and verify combine-audio ordering, validation,
source removal, ignored files, and failure safety.
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
		sed -n '1,200p' "$file" >&2
		exit 1
	fi
}

workspace="$test_root/Combine Workspace"
book="$workspace/Book Files"
mkdir -p "$book/Nested"
printf 'version=1\n' >"$workspace/.audiobook-workspace"
printf 'notes\n' >"$book/notes.txt"
printf 'nested\n' >"$book/Nested/01.mp3"

real_ffmpeg="$(command -v ffmpeg)"
trace_bin="$test_root/trace-bin"
manifest_trace="$test_root/manifest-trace"
mkdir "$trace_bin"
printf '%s\n' '#!/usr/bin/env bash' \
	'previous=""' \
	'for argument in "$@"; do' \
	'  if [[ "$previous" == "-i" ]]; then cp -- "$argument" "$COMBINE_MANIFEST_TRACE"; break; fi' \
	'  previous="$argument"' \
	'done' \
	'exec "$COMBINE_REAL_FFMPEG" "$@"' >"$trace_bin/ffmpeg"
chmod +x "$trace_bin/ffmpeg"

ffmpeg -v error -f lavfi -i 'sine=frequency=300:duration=0.1' -q:a 9 "$book/10 last.mp3"
ffmpeg -v error -f lavfi -i 'sine=frequency=400:duration=0.1' -q:a 9 -metadata title="First title" -metadata album="Combined album" -metadata artist="Test author" "$book/01 first.mp3"
ffmpeg -v error -f lavfi -i 'sine=frequency=500:duration=0.1' -q:a 9 -metadata title="Second title" "$book/2 reader's.mp3"

output="$workspace/combined.mp3"
(
	cd "$workspace"
	COMBINE_REAL_FFMPEG="$real_ffmpeg" COMBINE_MANIFEST_TRACE="$manifest_trace" \
		PATH="$trace_bin:$PATH" "$command_path" combine-audio "$book" "$output"
) >"$test_root/success-output"

require_output 'combined and removed 3 audio files' "$test_root/success-output"
[[ -s "$output" ]] || { echo 'combined output was not created' >&2; exit 1; }
[[ "$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=nw=1:nk=1 "$output")" == mp3 ]] || {
	echo 'combined output is not readable MP3 audio' >&2
	exit 1
}
output_title="$(ffprobe -v error -show_entries format_tags=title -of default=nw=1:nk=1 "$output")"
output_album="$(ffprobe -v error -show_entries format_tags=album -of default=nw=1:nk=1 "$output")"
output_artist="$(ffprobe -v error -show_entries format_tags=artist -of default=nw=1:nk=1 "$output")"
[[ "$output_title" == 'First title' ]] || { echo 'first-file title tag was not preserved' >&2; exit 1; }
[[ "$output_album" == 'Combined album' ]] || { echo 'album tag was not preserved' >&2; exit 1; }
[[ "$output_artist" == 'Test author' ]] || { echo 'artist tag was not preserved' >&2; exit 1; }
[[ ! -e "$book/01 first.mp3" && ! -e "$book/2 reader's.mp3" && ! -e "$book/10 last.mp3" ]] || {
	echo 'source audio files were not removed' >&2
	exit 1
}
[[ -f "$book/notes.txt" && -f "$book/Nested/01.mp3" ]] || {
	echo 'ignored files were changed' >&2
	exit 1
}
sed -n '2p' "$manifest_trace" | grep -F '01 first.mp3' >/dev/null || { echo 'first input was not naturally sorted' >&2; exit 1; }
sed -n '3p' "$manifest_trace" | grep -F "2 reader" >/dev/null || { echo 'second input was not naturally sorted' >&2; exit 1; }
sed -n '4p' "$manifest_trace" | grep -F '10 last.mp3' >/dev/null || { echo 'last input was not naturally sorted' >&2; exit 1; }

failure_dir="$workspace/Failure Files"
mkdir "$failure_dir"
ffmpeg -v error -f lavfi -i 'sine=frequency=600:sample_rate=44100:duration=0.1' "$failure_dir/01.flac"
ffmpeg -v error -f lavfi -i 'sine=frequency=700:sample_rate=48000:duration=0.1' "$failure_dir/02.flac"
before_first="$(sha256sum "$failure_dir/01.flac")"
before_second="$(sha256sum "$failure_dir/02.flac")"
set +e
(cd "$workspace" && "$command_path" combine-audio "$failure_dir" "$workspace/failure.flac") \
	>"$test_root/incompatible-output" 2>"$test_root/incompatible-error"
incompatible_status=$?
set -e
[[ "$incompatible_status" == 1 ]] || { echo "expected incompatible status 1, got $incompatible_status" >&2; exit 1; }
require_output 'incompatible audio stream' "$test_root/incompatible-error"
[[ ! -e "$workspace/failure.flac" ]] || { echo 'failure left an output file' >&2; exit 1; }
[[ "$(sha256sum "$failure_dir/01.flac")" == "$before_first" ]] || { echo 'failure changed first source' >&2; exit 1; }
[[ "$(sha256sum "$failure_dir/02.flac")" == "$before_second" ]] || { echo 'failure changed second source' >&2; exit 1; }

mixed_dir="$workspace/Mixed Files"
mkdir "$mixed_dir"
cp "$failure_dir/01.flac" "$mixed_dir/01.flac"
ffmpeg -v error -f lavfi -i 'sine=frequency=800:duration=0.1' -q:a 9 "$mixed_dir/02.mp3"
printf 'existing\n' >"$workspace/existing.flac"
set +e
(cd "$workspace" && "$command_path" combine-audio "$mixed_dir" "$workspace/mixed.flac") \
	>"$test_root/mixed-output" 2>"$test_root/mixed-error"
mixed_status=$?
(cd "$workspace" && "$command_path" combine-audio "$failure_dir" "$workspace/existing.flac") \
	>"$test_root/existing-output" 2>"$test_root/existing-error"
existing_status=$?
(cd "$workspace" && "$command_path" combine-audio "$failure_dir") \
	>"$test_root/usage-output" 2>"$test_root/usage-error"
usage_status=$?
"$command_path" combine-audio "$failure_dir" "$test_root/outside.flac" \
	>"$test_root/outside-output" 2>"$test_root/outside-error"
outside_status=$?
set -e

[[ "$mixed_status" == 1 ]] || { echo "expected mixed-type status 1, got $mixed_status" >&2; exit 1; }
[[ "$existing_status" == 1 ]] || { echo "expected existing-output status 1, got $existing_status" >&2; exit 1; }
[[ "$usage_status" == 2 ]] || { echo "expected usage status 2, got $usage_status" >&2; exit 1; }
[[ "$outside_status" == 1 ]] || { echo "expected outside-workspace status 1, got $outside_status" >&2; exit 1; }
require_output 'all input files must use' "$test_root/mixed-error"
require_output 'output already exists' "$test_root/existing-error"
require_output 'requires DIRECTORY and OUTPUT' "$test_root/usage-error"
require_output 'run this command inside an audiobook-convert workspace' "$test_root/outside-error"

echo 'combine-audio regression tests passed'
