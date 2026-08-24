#!/usr/bin/env bash
set -euo pipefail

# End-to-end regression coverage for legacy MP3 ID3 text conversion.
usage() {
	cat <<'HELP'
Usage: tests/fix-tag-encoding.sh

Create temporary MP3 fixtures and verify encoding repair, glob handling,
validation, metadata preservation, and source-audio preservation.
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

tag_value() {
	local tag="$1"
	local file="$2"

	exiftool -q -q -s3 "-$tag" -- "$file"
}

audio_hash() {
	ffmpeg -v error -nostdin -i "$1" -map 0:a:0 -c copy -f data - |
		sha256sum | awk '{print $1}'
}

create_fixture() {
	local output="$1"
	local frequency="$2"

	ffmpeg -v error -f lavfi -i "sine=frequency=$frequency:duration=0.1" \
		-metadata title='Ñòóäèÿ ÀÐÄÈÑ' \
		-metadata album='Àóäèîêíèãà' \
		-metadata artist='Àâòîð' \
		-metadata comment='Êîììåíòàðèé' \
		-metadata track=1 -id3v2_version 3 -write_id3v1 1 -q:a 9 "$output"
}

workspace="$test_root/Encoding Workspace"
book="$workspace/Book"
mkdir -p "$book"
printf 'version=1\n' >"$workspace/.audiobook-workspace"
create_fixture "$book/01.mp3" 440
create_fixture "$book/02.mp3" 550
chmod 640 "$book/01.mp3"

before_hash_1="$(audio_hash "$book/01.mp3")"
before_hash_2="$(audio_hash "$book/02.mp3")"
(cd "$workspace" && "$command_path" fix-tag-encoding WINDOWS-1251 "$book"/*.mp3) >"$test_root/update-output"

require_output "fixed tag encoding: $book/01.mp3" "$test_root/update-output"
require_output 'fixed tag encoding in 2 MP3 file(s)' "$test_root/update-output"
[[ "$(tag_value Title "$book/01.mp3")" == 'Студия АРДИС' ]] || { echo 'Title was not converted' >&2; exit 1; }
[[ "$(tag_value Album "$book/01.mp3")" == 'Аудиокнига' ]] || { echo 'Album was not converted' >&2; exit 1; }
[[ "$(tag_value Artist "$book/01.mp3")" == 'Автор' ]] || { echo 'Artist was not converted' >&2; exit 1; }
[[ "$(tag_value UserDefinedText "$book/01.mp3")" == '(comment) Комментарий' ]] || { echo 'custom text was not converted' >&2; exit 1; }
[[ "$(tag_value Track "$book/01.mp3")" == 1 ]] || { echo 'ASCII Track value changed' >&2; exit 1; }
[[ "$(audio_hash "$book/01.mp3")" == "$before_hash_1" ]] || { echo 'first audio stream changed' >&2; exit 1; }
[[ "$(audio_hash "$book/02.mp3")" == "$before_hash_2" ]] || { echo 'second audio stream changed' >&2; exit 1; }
[[ "$(stat -c '%a' "$book/01.mp3")" == 640 ]] || { echo 'file permissions changed' >&2; exit 1; }
if find "$book" -name '.fix-tag-encoding.*' -print -quit | grep -q .; then
	echo 'temporary files were not removed' >&2
	exit 1
fi

printf 'not audio\n' >"$book/broken.mp3"
printf 'not mp3\n' >"$book/notes.txt"
set +e
(cd "$workspace" && "$command_path" fix-tag-encoding WINDOWS-1251 "$book/notes.txt") >"$test_root/type-output" 2>"$test_root/type-error"
type_status=$?
(cd "$workspace" && "$command_path" fix-tag-encoding WINDOWS-1251 "$book/broken.mp3") >"$test_root/broken-output" 2>"$test_root/broken-error"
broken_status=$?
(cd "$workspace" && "$command_path" fix-tag-encoding NOT-A-CHARSET "$book/01.mp3") >"$test_root/encoding-output" 2>"$test_root/encoding-error"
encoding_status=$?
"$command_path" fix-tag-encoding WINDOWS-1251 "$book/01.mp3" >"$test_root/outside-output" 2>"$test_root/outside-error"
outside_status=$?
"$command_path" fix-tag-encoding WINDOWS-1251 >"$test_root/missing-output" 2>"$test_root/missing-error"
missing_status=$?
set -e

[[ "$type_status" == 1 ]] || { echo "expected non-MP3 status 1, got $type_status" >&2; exit 1; }
[[ "$broken_status" == 1 ]] || { echo "expected unreadable status 1, got $broken_status" >&2; exit 1; }
[[ "$encoding_status" == 2 ]] || { echo "expected encoding status 2, got $encoding_status" >&2; exit 1; }
[[ "$outside_status" == 1 ]] || { echo "expected workspace status 1, got $outside_status" >&2; exit 1; }
[[ "$missing_status" == 2 ]] || { echo "expected missing-file status 2, got $missing_status" >&2; exit 1; }
require_output 'not an MP3 file' "$test_root/type-error"
require_output 'unreadable MP3 audio' "$test_root/broken-error"
require_output 'unsupported encoding' "$test_root/encoding-error"
require_output 'run this command inside an audiobook-convert workspace' "$test_root/outside-error"
require_output 'at least one MP3_FILE is required' "$test_root/missing-error"

echo 'fix-tag-encoding regression tests passed'
