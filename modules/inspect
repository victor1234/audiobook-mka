# This module is sourced by ./audiobook-convert.
# Print command syntax, report contents, and read-only behavior.
stage::usage() {
	cat <<'HELP'
Usage: audiobook-convert inspect [--encoding CHARSET] [DIRECTORY]

Examine an audiobook source tree without changing it.

Arguments:
  DIRECTORY  Directory to inspect. Default: current working directory

Options:
  --encoding CHARSET  Decode mojibake-shaped paths and tags for display using
                      an iconv-compatible source charset.
  -h, --help        Show this help

The report describes the directory structure, audio files, common metadata,
external images, existing conversion artifacts, and problems that could affect
conversion. Audio rows show each file's metadata tag format or version.
External JPEG, PNG, and WebP images are listed with dimensions and size;
unrelated files remain in the Other files section. Warnings are advisory. Errors
identify inputs that block a current workflow stage and make the command exit
with status 1.

This read-only command can run directly on an original source directory; an
audiobook-convert workspace is not required. Without --encoding, paths and tags
are displayed exactly as the filesystem and media probe return them. Decoding
changes only the report; it never renames files or rewrites metadata.
HELP
}

# Parse the optional source directory and reject unsupported argument forms.
stage::parse_arguments() {
	target_dir="."
	encoding_mode=""
	encoding_seen=0

	while (($# > 0)); do
		case "$1" in
		-h | --help)
			stage::usage
			exit 0
			;;
		--encoding)
			if ((encoding_seen)); then
				echo "error: --encoding may be specified only once" >&2
				exit 2
			fi
			if (($# < 2)) || [[ -z "$2" || "$2" == -* ]]; then
				echo "error: --encoding requires a charset" >&2
				exit 2
			fi
			encoding_mode="$2"
			encoding_seen=1
			shift 2
			;;
		--encoding=*)
			if ((encoding_seen)); then
				echo "error: --encoding may be specified only once" >&2
				exit 2
			fi
			encoding_mode="${1#*=}"
			if [[ -z "$encoding_mode" ]]; then
				echo "error: --encoding requires a charset" >&2
				exit 2
			fi
			encoding_seen=1
			shift
			;;
		--)
			shift
			if (($# > 0)); then
				target_dir="$1"
				shift
			fi
			break
			;;
		-*)
			echo "error: unknown option: $1" >&2
			stage::usage >&2
			exit 2
			;;
		*)
			target_dir="$1"
			shift
			break
			;;
		esac
	done

	if (($# > 0)); then
		echo "error: too many arguments" >&2
		stage::usage >&2
		exit 2
	fi
}

# Validate the requested source charset before inspecting any files.
stage::validate_encoding() {
	[[ -n "$encoding_mode" ]] || return 0
	if [[ ! "$encoding_mode" =~ ^[[:alnum:]_.-]+$ ]] ||
		! iconv -f "$encoding_mode" -t UTF-8 </dev/null >/dev/null 2>&1; then
		echo "error: unsupported encoding: $encoding_mode" >&2
		exit 2
	fi
}

# Resolve the source root and discover naturally ordered audio and image inputs.
stage::validate_target() {
	if [[ ! -d "$target_dir" ]]; then
		echo "error: directory not found: $target_dir" >&2
		exit 1
	fi

	target_root="$(realpath -e -- "$target_dir")"
	mapfile -d '' audio_files < <(common::find_audio_files "$target_root")
	mapfile -d '' image_files < <(find "$target_root" -type f \
		\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
		-print0 | sort -zV)
	if ((${#audio_files[@]} == 0)); then
		echo "error: no supported audio files found in $target_dir" >&2
		exit 1
	fi
}

# Return a path relative to the resolved source root for stable report keys.
stage::relative_path() {
	local path="$1"
	if [[ "$path" == "$target_root" ]]; then
		printf '.'
	else
		printf '%s' "${path#"$target_root"/}"
	fi
}

# Escape control characters that would corrupt tabular or line-oriented output.
stage::display_value() {
	local value="$1"
	value=${value//$'\t'/\\t}
	value=${value//$'\n'/\\n}
	value=${value//$'\r'/\\r}
	printf '%s' "$value"
}

# Round seconds to the nearest whole second and format them as H:MM:SS.
stage::format_duration() {
	local seconds="$1"
	awk -v seconds="$seconds" 'BEGIN {
    total = int(seconds + 0.5)
    hours = int(total / 3600)
    minutes = int((total % 3600) / 60)
    secs = total % 60
    printf "%d:%02d:%02d", hours, minutes, secs
  }'
}

# Format byte counts with IEC units while retaining useful precision.
stage::format_size() {
	local bytes="$1"
	awk -v bytes="$bytes" 'BEGIN {
    split("B KiB MiB GiB TiB PiB", units, " ")
    unit = 1
    value = bytes
    while (value >= 1024 && unit < 6) {
      value /= 1024
      unit++
    }
    if (unit == 1) printf "%d %s", value, units[unit]
    else printf "%.1f %s", value, units[unit]
  }'
}

# Record one report-wide advisory finding and increment the summary total.
stage::add_warning() {
	warnings+=("$1")
	((total_warning_count += 1))
}

# Record one report-wide blocking finding and increment the summary total.
stage::add_error() {
	errors+=("$1")
	((total_error_count += 1))
}

# Append a compact issue marker to the current audio-file row.
stage::append_file_issue() {
	local issue="$1"
	if [[ -n "$current_issues" ]]; then
		current_issues+="; "
	fi
	current_issues+="$issue"
}

# Record and aggregate an advisory issue for the current audio file.
stage::add_file_warning() {
	local label="$1"
	stage::append_file_issue "W:$label"
	((file_warning_counts["$label"] += 1))
	((total_warning_count += 1))
}

# Record and aggregate a blocking issue for the current audio file.
stage::add_file_error() {
	local label="$1"
	stage::append_file_issue "E:$label"
	((file_error_counts["$label"] += 1))
	((total_error_count += 1))
}

# Expand compact per-file issue labels for the aggregate Findings section.
stage::issue_description() {
	case "$1" in
	"unreadable audio") printf 'unreadable or unrecognized audio' ;;
	"missing duration") printf 'duration unavailable' ;;
	"missing Track") printf 'missing Track tag' ;;
	"duplicate Track") printf 'duplicate Track in one directory' ;;
	"Track gap") printf 'Track sequence gap' ;;
	"Track out of order") printf 'Track out of natural file order' ;;
	"nonnumeric Track") printf 'nonnumeric Track tag' ;;
	"missing Title") printf 'missing MP3 Title tag' ;;
	"invalid UTF-8 path") printf 'invalid UTF-8 path' ;;
	"encoding decode failed") printf 'requested encoding could not be decoded' ;;
	*) printf '%s' "$1" ;;
	esac
}

# Recover the legacy bytes that were mistakenly converted through Windows-1252.
stage::recover_mojibake_bytes() {
	local value="$1"
	printf '%s' "$value" | iconv -f UTF-8 -t WINDOWS-1252 2>/dev/null
}

# Report whether a value was selected by the per-file jq mojibake filter.
stage::is_encoding_candidate() {
	local value="$1"
	local candidates_name="$2"
	local -n candidates="$candidates_name"
	local candidate
	for candidate in "${candidates[@]:11}"; do
		[[ "$candidate" == "$value" ]] && return 0
	done
	return 1
}

# Decode one selected display value while leaving non-candidates untouched.
stage::decode_display_value() {
	local value="$1"
	local candidates_name="$2"
	local charset="$3"
	decoded_value="$value"
	stage::is_encoding_candidate "$value" "$candidates_name" || return 0
	decoded_value="$(stage::recover_mojibake_bytes "$value" |
		iconv -f "$charset" -t UTF-8 2>/dev/null)" || return 1
}

# Save decoded basenames separately from the real paths used for file access.
stage::record_display_path() {
	local actual="$1"
	local displayed="$2"
	while [[ "$actual" != "." ]]; do
		display_names["$actual"]="$(basename -- "$displayed")"
		actual="$(dirname -- "$actual")"
		displayed="$(dirname -- "$displayed")"
	done
}

# Sort and join associative-array keys for deterministic summary values.
stage::join_keys() {
	local -n values="$1"
	printf '%s\n' "${!values[@]}" | sort -V | paste -sd ',' - | sed 's/,/, /g'
}

# Collect metadata tag formats in one recursive ExifTool process instead of one
# process per audio file. ExifTool group names are normalized for report output,
# and files containing multiple systems retain every label. The `none` fallback
# means no requested tag group was recognized, not that the audio is invalid.
# Restricting groups avoids loading unrelated technical metadata.
stage::probe_tag_formats() {
	declare -gA tag_formats=()
	local tag_json source label index
	local -a parsed_tags=()

	tag_json="$(exiftool -r -j -G1 -a \
		-ID3:all -Vorbis:all -ItemList:all -UserData:all \
		-RIFF:all -ASF:all -APE:all \
		-ext aac -ext alac -ext flac -ext m4a -ext m4b -ext mp3 \
		-ext oga -ext ogg -ext opus -ext wav -ext wma \
		"$target_root" 2>/dev/null)" || tag_json='[]'

	mapfile -d '' parsed_tags < <(
		jq -nrj --argjson files "$tag_json" '
      def has_group($group): any(keys[]; startswith($group + ":"));
      $files[]
      | . as $file
      | [
          (if has_group("ID3v2_2") then "ID3v2.2" else empty end),
          (if has_group("ID3v2_3") then "ID3v2.3" else empty end),
          (if has_group("ID3v2_4") then "ID3v2.4" else empty end),
          (if has_group("ID3v1") then "ID3v1" else empty end),
          (if has_group("Vorbis") then "Vorbis" else empty end),
          (if has_group("ItemList") or has_group("UserData") then "MP4" else empty end),
          (if has_group("RIFF") then "RIFF" else empty end),
          (if has_group("ASF") then "ASF" else empty end),
          (if has_group("APE") then "APEv2" else empty end)
        ] as $formats
      | $file.SourceFile,
        (if ($formats | length) == 0 then "none" else ($formats | join(" + ")) end)
      | tostring + "\u0000"
    '
	)

	for ((index = 0; index + 1 < ${#parsed_tags[@]}; index += 2)); do
		source="${parsed_tags[$index]}"
		label="${parsed_tags[$((index + 1))]}"
		tag_formats["${source#"$target_root"/}"]="$label"
	done
}

# Probe every audio file and build report rows, aggregates, and findings.
stage::probe_files() {
	declare -ga warnings=()
	declare -ga errors=()
	declare -gA file_rows=()
	declare -gA directory_durations=()
	declare -gA formats=()
	declare -gA codecs=()
	declare -gA sample_rates=()
	declare -gA channel_counts=()
	declare -gA albums=()
	declare -gA artists=()
	declare -gA planned_targets=()
	declare -gA previous_tracks=()
	declare -gA file_error_counts=()
	declare -gA file_warning_counts=()
	declare -gA display_names=()
	local file relative parent track title album artist extension media_info ancestor tag_format
	local duration codec sample_rate channels format_name attached_pic target track_id has_audio
	local display_duration display_relative cover value size track_number previous_track
	local encoding_label decoding_failed
	local -a parsed=()

	total_duration=0
	total_size=0
	artwork_count=0
	non_mp3_count=0
	total_error_count=0
	total_warning_count=0

	for file in "${audio_files[@]}"; do
		relative="$(stage::relative_path "$file")"
		tag_format="${tag_formats[$relative]:-none}"
		parent="$(dirname -- "$relative")"
		extension="${file##*.}"
		extension="${extension,,}"
		current_issues=""

		media_info="$(mediainfo --Output=JSON "$file" 2>/dev/null)" || media_info=""
		if [[ -z "$media_info" ]]; then
			stage::add_file_error "unreadable audio"
			file_rows["$relative"]=$'\t\t'"$tag_format"$'\t?'$'\t'"$extension"$'\t?'$'\t'"$current_issues"
			continue
		fi

		# MediaInfo normalizes tags into a General record and technical fields
		# into an Audio record. Emit fixed fields, then mojibake candidates.
		mapfile -d '' parsed < <(
			jq -nrj --argjson media_info "$media_info" --arg relative "$relative" '
        def mojibake_candidate:
          tostring as $text
          | ($text | explode | map(select(. >= 192 and . <= 255)) | length) as $western
          | ($text | explode | map(select(. > 32)) | length) as $visible
          | $western >= 3 and ($western * 2 >= $visible);
        ($media_info.media.track // []) as $tracks
        | ([ $tracks[] | select(."@type" == "General") ][0] // {}) as $general
        | ([ $tracks[] | select(."@type" == "Audio") ][0] // {}) as $audio
        | ($general.Track_Position // "" | tostring) as $track_position
        | ($general.Track_Position_Total // "" | tostring) as $track_total
        | (if $track_position != "" and $track_total != "" and ($track_position | contains("/") | not)
           then $track_position + "/" + $track_total else $track_position end) as $track
        | ([ $audio.Format, $audio.Format_Profile, $audio.CodecID ]
           | map(select(. != null and . != "") | tostring) | join(" / ")) as $codec
        | ($audio.Duration // "0" | tonumber? // 0) as $duration_number
        | [
            $track,
            ($general.Title // $general.Track // ""),
            ($general.Album // ""),
            ($general.Album_Performer // $general.Performer // ""),
            ($audio.Duration // "" | tostring),
            ($general.Format // ""),
            $codec,
            ($audio.SamplingRate // "" | tostring),
            ($audio.Channels // "" | tostring),
            (if $general.Cover == "Yes" then "1" else "0" end),
            (if ($audio | length) > 0 and $audio.Format != null and $audio.Format != "" and $duration_number > 0
             then "1" else "0" end)
          ]
          + ([ $relative, $track, $general.Title, $general.Track, $general.Album,
               ($general.Album_Performer // $general.Performer) ]
             | map(select(. != null and mojibake_candidate)))
        | .[] | tostring + "\u0000"
      '
		)
		if ((${#parsed[@]} < 11)); then
			stage::add_file_error "unreadable audio"
			file_rows["$relative"]=$'\t\t'"$tag_format"$'\t?'$'\t'"$extension"$'\t?'$'\t'"$current_issues"
			continue
		fi

		track="$(common::trim "${parsed[0]}")"
		title="$(common::trim "${parsed[1]}")"
		album="${parsed[2]}"
		artist="${parsed[3]}"
		duration="${parsed[4]}"
		format_name="${parsed[5]}"
		codec="${parsed[6]}"
		sample_rate="${parsed[7]}"
		channels="${parsed[8]}"
		attached_pic="${parsed[9]}"
		has_audio="${parsed[10]}"
		display_relative="$relative"

		# Decode only dense mojibake candidates, leaving all other report text
		# exactly as returned by the filesystem and media probe.
		if [[ -n "$encoding_mode" ]] && ((${#parsed[@]} > 11)); then
			encoding_label="${encoding_mode^^}"
			decoding_failed=0
			stage::decode_display_value "$relative" parsed "$encoding_mode" || decoding_failed=1
			display_relative="$decoded_value"
			stage::decode_display_value "$track" parsed "$encoding_mode" || decoding_failed=1
			track="$decoded_value"
			stage::decode_display_value "$title" parsed "$encoding_mode" || decoding_failed=1
			title="$decoded_value"
			stage::decode_display_value "$album" parsed "$encoding_mode" || decoding_failed=1
			album="$decoded_value"
			stage::decode_display_value "$artist" parsed "$encoding_mode" || decoding_failed=1
			artist="$decoded_value"
			if ((decoding_failed)); then
				stage::add_file_warning "encoding decode failed"
			else
				stage::add_file_warning "decoded $encoding_label"
			fi
		fi
		stage::record_display_path "$relative" "$display_relative"
		if [[ "$has_audio" != "1" ]]; then
			stage::add_file_error "unreadable audio"
			file_rows["$relative"]="$(stage::display_value "$track")"$'\t'"$(stage::display_value "$title")"$'\t'"$tag_format"$'\t?'$'\t'"${codec:-$extension}"$'\t?'$'\t'"$current_issues"
			continue
		fi

		if [[ ! "$duration" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
			stage::add_file_error "missing duration"
			display_duration="?"
		else
			display_duration="$(stage::format_duration "$duration")"
			total_duration="$(awk -v a="$total_duration" -v b="$duration" 'BEGIN { printf "%.6f", a + b }')"
			ancestor="$parent"
			while [[ "$ancestor" != "." ]]; do
				directory_durations["$ancestor"]="$(awk -v a="${directory_durations[$ancestor]:-0}" -v b="$duration" 'BEGIN { printf "%.6f", a + b }')"
				ancestor="$(dirname -- "$ancestor")"
			done
		fi

		size="$(stat -c '%s' "$file")"
		((total_size += size))
		# stage::join_keys reads this map through a Bash nameref.
		# shellcheck disable=SC2034
		formats["${format_name:-$extension}"]=1
		[[ -n "$codec" ]] && codecs["$codec"]=1
		[[ -n "$sample_rate" ]] && sample_rates["$sample_rate"]=1
		[[ -n "$channels" ]] && channel_counts["$channels"]=1
		[[ -n "$album" ]] && ((albums["$album"] += 1))
		[[ -n "$artist" ]] && ((artists["$artist"] += 1))

		if ((attached_pic > 0)); then
			((artwork_count += 1))
			cover="yes"
		else
			cover="no"
		fi

		if [[ -z "$track" ]]; then
			stage::add_file_error "missing Track"
		else
			track_id="${track%%/*}"
			track_id="$(common::trim "$track_id")"
			target="$parent/$track_id.$extension"
			if [[ -n "${planned_targets[$target]:-}" ]]; then
				stage::add_file_error "duplicate Track"
			else
				planned_targets["$target"]="$relative"
			fi
			if [[ "$track_id" =~ ^[0-9]+$ ]]; then
				track_number=$((10#$track_id))
				previous_track="${previous_tracks[$parent]:-}"
				if [[ -n "$previous_track" ]] && ((track_number > previous_track + 1)); then
					stage::add_file_warning "Track gap"
				elif [[ -n "$previous_track" ]] && ((track_number < previous_track)); then
					stage::add_file_warning "Track out of order"
				fi
				previous_tracks["$parent"]="$track_number"
			else
				stage::add_file_warning "nonnumeric Track"
			fi
		fi

		if [[ "$extension" == "mp3" ]]; then
			[[ -n "$title" ]] || stage::add_file_error "missing Title"
		else
			((non_mp3_count += 1))
		fi

		if ! printf '%s' "$relative" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1; then
			stage::add_file_warning "invalid UTF-8 path"
		fi
		file_rows["$relative"]="$(stage::display_value "$track")"$'\t'"$(stage::display_value "$title")"$'\t'"$tag_format"$'\t'"$display_duration"$'\t'"${codec:-$extension}"$'\t'"$cover"$'\t'"$current_issues"
	done

	if ((non_mp3_count > 0)); then
		stage::add_error "$non_mp3_count non-MP3 audio file(s) will be omitted by the current chapters command"
	fi
	if ((artwork_count == 0)); then
		stage::add_warning "no embedded cover artwork was found"
	fi
	((${#codecs[@]} <= 1)) || stage::add_warning "audio uses mixed codecs: $(stage::join_keys codecs)"
	((${#sample_rates[@]} <= 1)) || stage::add_warning "audio uses mixed sample rates: $(stage::join_keys sample_rates)"
	((${#channel_counts[@]} <= 1)) || stage::add_warning "audio uses mixed channel counts: $(stage::join_keys channel_counts)"
	((${#albums[@]} <= 1)) || stage::add_warning "Album metadata has ${#albums[@]} different values"
	((${#artists[@]} <= 1)) || stage::add_warning "Artist metadata has ${#artists[@]} different values"
}

# Inspect external images without changing or selecting any source file.
stage::probe_images() {
	declare -ga image_rows=()
	local file relative extension details codec width height dimensions size issues

	for file in "${image_files[@]}"; do
		relative="$(stage::relative_path "$file")"
		extension="${file##*.}"
		extension="${extension,,}"
		size="$(stage::format_size "$(stat -c '%s' "$file")")"
		issues=""

		details="$(ffprobe -v error -select_streams v:0 \
			-show_entries stream=codec_name,width,height \
			-of csv=p=0 "$file" 2>/dev/null)" || details=""
		IFS=',' read -r codec width height <<<"$details"
		if [[ -z "$codec" || ! "$width" =~ ^[0-9]+$ || ! "$height" =~ ^[0-9]+$ ]]; then
			codec="${extension^^}"
			dimensions="?"
			issues="W:unreadable image"
			stage::add_warning "$relative: unreadable image"
		else
			dimensions="${width}x${height}"
		fi

		image_rows+=("$(stage::display_value "$relative")"$'\t'"${codec^^}"$'\t'"$dimensions"$'\t'"$size"$'\t'"$issues")
	done
}

# Print discovered external images and their technical properties.
stage::print_images() {
	echo
	echo "Images"
	{
		printf 'FILE\tFORMAT\tDIMENSIONS\tSIZE\tISSUES\n'
		if ((${#image_rows[@]} == 0)); then
			printf 'none\t\t\t\t\n'
		else
			printf '%s\n' "${image_rows[@]}"
		fi
	} | column -t -s $'\t'
}

# Print source location and audiobook-wide media and metadata totals.
stage::print_summary() {
	local location="original source"
	local found_workspace=""
	if found_workspace="$(common::find_workspace "$target_root" 2>/dev/null)"; then
		location="workspace: $found_workspace"
	fi

	printf 'Audiobook: %s\n' "$target_root"
	printf 'Location:  %s\n' "$location"
	printf 'Audio:     %d files, %s, %s\n' "${#audio_files[@]}" \
		"$(stage::format_duration "$total_duration")" "$(stage::format_size "$total_size")"
	printf 'Formats:   %s\n' "$(stage::join_keys formats)"
	printf 'Artwork:   %d of %d audio files\n' "$artwork_count" "${#audio_files[@]}"
	if ((${#albums[@]} > 0)); then
		printf 'Albums:    %s\n' "$(stage::join_keys albums)"
	fi
	if ((${#artists[@]} > 0)); then
		printf 'Artists:   %s\n' "$(stage::join_keys artists)"
	fi
}

# Emit each immediate child once; audio_files natural order determines tree order.
stage::tree_children() {
	local parent="$1"
	local file relative remainder component child node
	local -A seen=()

	for file in "${audio_files[@]}"; do
		relative="$(stage::relative_path "$file")"
		if [[ -n "$parent" ]]; then
			[[ "$relative" == "$parent/"* ]] || continue
			remainder="${relative#"$parent"/}"
		else
			remainder="$relative"
		fi

		if [[ "$remainder" == */* ]]; then
			component="${remainder%%/*}"
			child="${parent:+$parent/}$component"
			node="D$child"
		else
			node="F$relative"
		fi
		if [[ -z "${seen[$node]:-}" ]]; then
			seen["$node"]=1
			printf '%s\0' "$node"
		fi
	done
}

# Render directory totals and file metadata in one recursive tree table.
stage::print_tree_nodes() {
	local parent="$1"
	local prefix="$2"
	local index node node_type path connector child_prefix name duration
	local -a children=()

	mapfile -d '' children < <(stage::tree_children "$parent")
	for index in "${!children[@]}"; do
		node="${children[$index]}"
		node_type="${node:0:1}"
		path="${node:1}"
		connector="├── "
		child_prefix="$prefix│   "
		if ((index == ${#children[@]} - 1)); then
			connector="└── "
			child_prefix="$prefix    "
		fi
		name="$(stage::display_value "${display_names[$path]:-$(basename -- "$path")}")"

		if [[ "$node_type" == "D" ]]; then
			duration="$(stage::format_duration "${directory_durations[$path]:-0}")"
			printf '%s%s%s/\t\t\t\t%s\t\t\t\n' \
				"$prefix" "$connector" "$name" "$duration"
			stage::print_tree_nodes "$path" "$child_prefix"
		else
			printf '%s%s%s\t%s\n' "$prefix" "$connector" "$name" "${file_rows[$path]}"
		fi
	done
}

# Print the combined audio hierarchy and per-file metadata table.
stage::print_audio_tree() {
	echo
	echo "Audio tree"
	{
		printf 'FILE\tTRACK\tTITLE\tTAGS\tDURATION\tCODEC\tCOVER\tISSUES\n'
		stage::print_tree_nodes "" ""
	} | column -t -s $'\t'
}

# Print whether one expected conversion artifact exists below the source root.
stage::artifact_status() {
	local path="$1"
	local label="$2"
	if [[ -e "$target_root/$path" ]]; then
		printf '%-18s present: %s\n' "$label" "$path"
	else
		printf '%-18s not created\n' "$label"
	fi
}

# Report conversion artifacts and validate any artifacts already present.
stage::inspect_artifacts() {
	local mka
	echo
	echo "Conversion artifacts"
	stage::artifact_status "chapters.txt" "Chapters"
	stage::artifact_status "tags.xml" "Global tags"
	stage::artifact_status "images/cover.jpg" "Selected cover"

	if [[ -f "$target_root/chapters.txt" ]] && ! awk '
		/^CHAPTER[0-9]+=[0-9][0-9]:[0-9][0-9]:[0-9][0-9]([.][0-9]+)?$/ { starts++; next }
		/^CHAPTER[0-9]+NAME=/ { names++; next }
		{ invalid = 1 }
		END { exit invalid || starts == 0 || starts != names }
	' "$target_root/chapters.txt"; then
		stage::add_error "chapters.txt: malformed simple chapter data"
	fi

	if [[ -f "$target_root/tags.xml" ]] && ! xmllint --noout "$target_root/tags.xml" 2>/dev/null; then
		stage::add_error "tags.xml: malformed XML"
	fi
	if [[ -f "$target_root/images/cover.jpg" ]] &&
		! ffprobe -v error "$target_root/images/cover.jpg" >/dev/null 2>&1; then
		stage::add_error "images/cover.jpg: unreadable cover image"
	fi

	mapfile -d '' mka_files < <(find "$target_root" -type f -iname '*.mka' -print0 | sort -zV)
	if ((${#mka_files[@]} == 0)); then
		printf '%-18s not created\n' "MKA output"
	else
		printf '%-18s %d file(s)\n' "MKA output" "${#mka_files[@]}"
		for mka in "${mka_files[@]}"; do
			if ! ffprobe -v error "$mka" >/dev/null 2>&1; then
				stage::add_error "$(stage::relative_path "$mka"): unreadable MKA output"
			fi
		done
	fi
}

# List files not already classified as supported audio or external images.
stage::print_other_files() {
	local -A excluded_files=()
	local file found=0
	for file in "${audio_files[@]}"; do
		excluded_files["$file"]=1
	done
	for file in "${image_files[@]}"; do
		excluded_files["$file"]=1
	done

	echo
	echo "Other files"
	while IFS= read -r -d '' file; do
		[[ -n "${excluded_files[$file]:-}" ]] && continue
		printf '  %s\n' "$(stage::display_value "$(stage::relative_path "$file")")"
		found=1
	done < <(find "$target_root" -type f -print0 | sort -zV)
	((found)) || echo "  none"
}

# Print aggregated blocking errors, advisory warnings, and final totals.
stage::print_findings() {
	local finding label description count noun
	echo
	echo "Findings"
	if ((total_error_count == 0 && total_warning_count == 0)); then
		echo "  No problems found."
		return
	fi
	while IFS= read -r label; do
		[[ -n "$label" ]] || continue
		count="${file_error_counts[$label]}"
		noun="files"
		((count == 1)) && noun="file"
		description="$(stage::issue_description "$label")"
		printf '  ERROR (%d %s): %s\n' "$count" "$noun" "$description"
	done < <(printf '%s\n' "${!file_error_counts[@]}" | sort)
	for finding in "${errors[@]}"; do
		printf '  ERROR: %s\n' "$finding"
	done
	while IFS= read -r label; do
		[[ -n "$label" ]] || continue
		count="${file_warning_counts[$label]}"
		noun="files"
		((count == 1)) && noun="file"
		description="$(stage::issue_description "$label")"
		printf '  WARNING (%d %s): %s\n' "$count" "$noun" "$description"
	done < <(printf '%s\n' "${!file_warning_counts[@]}" | sort)
	for finding in "${warnings[@]}"; do
		printf '  WARNING: %s\n' "$finding"
	done
	printf '  Summary: %d error(s), %d warning(s)\n' "$total_error_count" "$total_warning_count"
}
# Orchestrate dependency checks, read-only probes, report sections, and exit status.
stage::run() {
	stage::parse_arguments "$@"
	common::require_commands column exiftool ffprobe find iconv jq mediainfo paste realpath sed sort stat xmllint || exit 1
	stage::validate_encoding
	stage::validate_target
	stage::probe_tag_formats
	stage::probe_files
	stage::probe_images
	stage::print_summary
	stage::print_audio_tree
	stage::print_images
	stage::inspect_artifacts
	stage::print_other_files
	stage::print_findings
	((total_error_count == 0))
}
