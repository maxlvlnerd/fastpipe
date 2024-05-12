#!/usr/bin/env -S nix shell nixpkgs#ffmpeg-headless --command bash
set -e
nix build ./
input_filename='-'
pipe_filename=
format='s16le'
rate='44100'
channels='1'
while [ "$1" != '' ]
do
    case "$1" in
        -p | --pipe    )  shift ; pipe_filename="$1" ;;
        -f | --format  )  shift ; format="$1"        ;;
        -r | --rate    )  shift ; rate="$1"          ;;
        -c | --channels)  shift ; channels="$1"      ;;
        -h | --help    )  usage ; exit 0             ;;
        -* )              echo "$0: invalid option '$1'"
                          usage ; exit 1             ;;
        *)                input_filename="$1"
    esac
    shift
done

[ "$pipe_filename" ] || {
	pipe_filename="$(mktemp -u)"
	mkfifo "$pipe_filename"
}
ffmpeg \
	    -loglevel panic \
            -re -i "$input_filename"     \
            -f "$format"                 \
            -ar "$rate"                  \
            -ac "$channels"              \
            '-' > "$pipe_filename" &
# trap
trap 'kill $!' EXIT
echo $pipe_filename
./result/bin/fastpipe -- $pipe_filename
