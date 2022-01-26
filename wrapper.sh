#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021-2022, Konstantin Demin

set -f

dir0=$(dirname "$0")
dir0=$(readlink -f "${dir0}")

## --- functions

distro_info() { "${dir0}/simple-csv.sh" "$@" ; }
distro_chan() { grep -Eo '^[^ ,]+' | tac | tr -s '[:space:]' ' ' ; }

is_latest() { printf '%s\n' "$1" | grep -qE -e "^$2( |\$)" ; }

## $1 - file with "distro_info distro channel"
## $2 - channel
chan_altname() {
	cut -d ',' -f 1 \
	< "$1" \
	| tr -s '[:space:]' '\n' \
	| grep -Fxv "$2" \
	| tr -s '[:space:]' ' '
}

## $1 - file with "distro_info distro channel"
## $2 - channel
chan_tag() {
	cut -d ',' -f 3 \
	< "$1" \
	| grep -Fxv "$2"
}

## $1 - file with "distro_info distro channel"
## $2 - channel
true_tag() {
	tail -n 1 \
	< "$1" \
	| cut -d ',' -f 1 \
	| tr -s '[:space:]' '\n' \
	| grep -Fx "$2"
}

## -- code itself

channels=$(distro_info "$1" | distro_chan)
case "$1" in
debian) channels=${channels}' unstable' ;;
## maybe handle it too?..
# ubuntu) channels=${channels}' devel' ;;
esac

t=$(mktemp)
for chan in ${channels} ; do
	distro_info "$1" "${chan}" > "$t"

	chan_list=${chan}

	altnames=$(chan_altname "$t" "${chan}")
	chan_list="${chan_list} ${altnames}"

	tag=$(chan_tag "$t" "${chan}")
	if [ -n "${tag}" ] ; then
		distro_info "$1" "${tag}" > "$t"
		tag_q=$(true_tag "$t" "${chan}")
		[ -n "${tag_q}" ] \
			&& chan_list="${chan_list} ${tag}"
	fi

	is_latest "${channels}" "${chan}" \
		&& chan_list="${chan_list} latest"

	## explicit word splitting
	# shellcheck disable=SC2086
	echo ${chan_list}
done
rm -f "$t"
