# Audiobooks

A Bash command for turning a directory of audio tracks into a single Matroska
Audio (`.mka`) audiobook with chapters, global metadata, and cover art.

The processing stages operate on one audiobook directory tree at a time. Source
paths are sorted naturally so numbered directories and tracks retain their
intended playback order.

## Requirements

The audiobook command requires Bash and does not support execution with POSIX
`sh` or other shells.

The project uses [mise](https://mise.jdx.dev/) to add the repository root to `PATH` and
to manage development tools, including the
[prek](https://prek.j178.dev/) pre-commit runner. Install the tools declared in
`mise.toml` with:

```bash
mise install
```

The audiobook stages also require these system commands:

- `exiftool`
- `ffmpeg` and `ffprobe`
- `jq`
- `mediainfo`
- `mid3iconv` (provided by Mutagen; `python3-mutagen` on Debian/Ubuntu)
- `column`
- `mkvmerge`
- `xmllint`
- standard Unix tools including `awk`, `cp`, `find`, `mktemp`, `mv`, `realpath`,
  `rm`, `sort`, and `sha256sum`

Activate the mise environment from the repository root before using the
commands:

```bash
eval "$(mise activate bash)"
```

Alternatively, prefix an individual command with `mise exec --`.

## CLI

Use the `audiobook-convert` entrypoint to run any processing stage:

```bash
audiobook-convert --help
audiobook-convert inspect ./book
audiobook-convert workspace ./book
audiobook-convert fix-tag-encoding WINDOWS-1251 ./*.mp3
audiobook-convert track-tags .
audiobook-convert set-track-number --dry-run .
audiobook-convert rename-track-id --dry-run .
audiobook-convert chapters chapters.txt
```

Global options are parsed before the subcommand. Use `--` to stop global option
parsing when needed. Each subcommand sources the corresponding numbered module
and receives its remaining arguments unchanged; command-specific options stay
with that module. Stages remain independently runnable through their
subcommands. Use `audiobook-convert help COMMAND` for a stage's detailed help,
for example:

```bash
audiobook-convert help create-mka
```

The entrypoint provides these stage subcommands:

| Subcommand | Sourced module | Stage |
| ----------------- | -------------------- | ----- |
| `workspace` | `workspace.sh` | setup |
| `clean-workspace` | `clean-workspace.sh` | cleanup |
| `inspect` | `inspect.sh` | inspection |
| `fix-tag-encoding` | `fix-tag-encoding.sh` | utility |
| `track-tags` | `0-track-tags.sh` | 0 |
| `set-track-number` | `set-track-number.sh` | utility |
| `rename-track-id` | `1-rename-track-id.sh` | 1 |
| `chapters` | `2-chapters.sh` | 2 |
| `images` | `3-images.sh` | 3 |
| `audiobook-tags` | `4-audiobook-tags.sh` | 4 |
| `create-mka` | `5-create-mka.sh` | 5 |

Successful commands and help requests exit with status 0. Invalid CLI usage,
including a missing or unknown command or option, exits with status 2 after
printing an error to standard error. Processing failures exit with status 1.

The additional `show-tags` utility is available as `audiobook-convert show-tags`.

## Workflow

First inspect the original audiobook to understand its nested structure,
metadata, media properties, artwork, and any problems that could affect the
conversion workflow:

```bash
audiobook-convert inspect ./book
```

The audio tree includes each file's metadata tag format/version. The report
also lists external JPEG, PNG, and WebP images separately with their dimensions
and size; unrelated files remain under `Other files`.

By default, inspection displays paths and metadata exactly as they are returned
by the filesystem and media probes. To decode mojibake for display, provide its
known iconv-compatible source charset explicitly:

```bash
audiobook-convert inspect --encoding WINDOWS-1251 ./book
```

Decoded text and paths exist only in the report; inspection never renames source
files or rewrites embedded tags.

Inspection is read-only and does not require a workspace. It exits successfully
when it finds only advisory warnings and fails when it finds an issue that
blocks a current conversion stage, such as unreadable media or required missing
track metadata.

Then copy the original audiobook into an isolated workspace. Modifying stages
refuse to run outside a workspace, while `track-tags` and `show-tags` remain
available for read-only source inspection. No automatic pipeline is provided.

1. Create the workspace and enter it:

   ```bash
   audiobook-convert workspace ./book
   cd ./book.audiobook-work
   ```

   The default workspace is a persistent sibling of the source. The complete
   source tree is copied without hard links, so subsequent changes cannot alter
   original files.

1. If inspection shows legacy-encoded MP3 tags, convert every ID3 text and
   comment frame from the known source encoding to Unicode. File globs are
   expanded by the shell, so leave the pattern unquoted:

   ```bash
   audiobook-convert fix-tag-encoding WINDOWS-1251 ./*.mp3
   ```

   The command requires `mid3iconv` and writes Unicode ID3v2 metadata (normally
   ID3v2.4). It preserves ASCII and incompatible values, specialized frames
   such as lyrics and artwork descriptions, binary metadata, and audio data.

1. Inspect the source track numbers and titles:

   ```bash
   audiobook-convert track-tags .
   ```

1. If the Track tags need correction, preview and then assign sequential Track
   values to naturally sorted audio files directly in one directory:

   ```bash
   audiobook-convert set-track-number --dry-run ./part-1
   audiobook-convert set-track-number ./part-1
   ```

   This command does not recurse into subdirectories. It preserves audio
   streams without re-encoding and ignores non-audio files.

1. Preview and then apply filenames based on each file's `Track` tag:

   ```bash
   audiobook-convert rename-track-id --dry-run .
   audiobook-convert rename-track-id .
   ```

1. Create chapter entries from recursively discovered, naturally sorted MP3
   files. Chapter names come from the files' `Title` tags; every MP3 becomes one
   chapter even when the files are arranged in nested directories:

   ```bash
   audiobook-convert chapters chapters.txt
   ```

1. Extract embedded artwork, remove exact duplicates, and select the largest
   image as `images/cover.jpg`:

   ```bash
   audiobook-convert images images
   ```

1. Enter the audiobook's global metadata interactively:

   ```bash
   audiobook-convert audiobook-tags tags.xml
   ```

1. Merge the tracks, chapters, tags, and cover into an MKA file:

   ```bash
   audiobook-convert create-mka chapters.txt tags.xml images .
   ```

   When no output path is supplied, the filename is generated from the
   `AUTHOR`, `TITLE`, and optional `NARRATOR` tags:

   ```text
   AUTHOR - TITLE {NARRATOR}.mka
   ```

   To choose the output path explicitly, pass it as the fifth argument:

   ```bash
   audiobook-convert create-mka chapters.txt tags.xml images . audiobook.mka
   ```

After copying the finished MKA elsewhere, leave the workspace for later reuse or
remove it explicitly from its parent directory:

```bash
audiobook-convert clean-workspace ./book.audiobook-work
```

Cleanup refuses unmarked directories and symbolic links.

Every stage provides detailed command help:

```bash
audiobook-convert create-mka --help
```

## Additional commands

Inspect the raw ID3 metadata in a source audio file with:

```bash
audiobook-convert show-tags track.mp3
```

When invoking a script through mise while working in another directory, pass
the absolute directory where appropriate:

```bash
mise exec -- audiobook-convert track-tags "$PWD"
```

## Project structure

```text
.
├── audiobook-convert      # Executable CLI entrypoint
├── mise.toml               # Development tools and repository PATH configuration
├── modules/                 # Sourced stage modules and proven shared helpers
└── data/                   # Local source material and generated audiobook data
```

`modules/common.sh` contains only helpers already used by at least two stage
modules. Argument handling, validation, transformations, and output behavior
remain in the module for the stage that owns them.

Stages recursively process files beneath the selected audiobook directory.
Workspace markers are versioned, and every modifying stage validates that its
inputs and outputs resolve inside the marked workspace.
Existing MKA outputs and sidecar files are excluded from source-audio
discovery, and directory symlinks are not followed.

## Development

Install the repository's Git pre-commit hook after installing the mise tools:

```bash
mise exec -- prek install
```

Run shfmt, ShellCheck, and mdformat across all supported files before committing
changes:

```bash
mise exec -- prek run --all-files
```

To run one check independently, continue to invoke it through prek:

```bash
mise exec -- prek run shfmt --all-files
mise exec -- prek run shellcheck --all-files
mise exec -- prek run mdformat --all-files
```

Keep modules documented with focused comments and useful command help output.
