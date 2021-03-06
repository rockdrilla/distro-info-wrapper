#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause
# (c) 2021-2022, Konstantin Demin

set -f

info_dir='/usr/share/distro-info'
info_web='https://debian.pages.debian.net/distro-info-data'

dir0=$(dirname "$0")

## $1 - distro name
distro_known() {
	case "$1" in
	debian|ubuntu) return 0 ;;
	*) return 1 ;;
	esac
}

## $1 - distro name
distro_birth() {
	case "$1" in
	ubuntu) echo '2004-10-20' ;;
	## return Debian's in all other cases
	*) echo '1993-08-16' ;;
	esac
}

## $1 - url
curl_uri_response() {
	{
		echo 404
		curl -sSL -o /dev/null -D - "$1" \
		| sed -En '/^HTTP\/[.0-9]+ ([0-9]+)(| .+)$/{s//\1/;p;}'
	} | tail -n 1
}

## $1 - distro name
local_avail() {
	[ -s "${info_dir}/$1.csv" ]
}

## $1 - distro name
remote_avail() {
	curl_uri_response "${info_web}/$1.csv" \
	| grep -Fxq '200'
}

## $1 - distro name
## $2 - output file (or stdout if not specified)
remote_fetch() {
	curl -sSL ${2:+-o "$2"} "${info_web}/$1.csv"
}

## $1 - distro name
## $2 - release/series
local_query() {
	tail -n +2 "${info_dir}/$1.csv" \
	| reformat \
	| reparse \
	| lookup "$2"
}

## $1 - input file with fetched data from remote source
## $2 - release/series
remote_query() {
	remote_fetch "$1" \
	| tail -n +2 \
	| reformat \
	| reparse \
	| lookup "$2"
}

reformat() {
	"${dir0}/reformat.awk"
}

reparse() {
	"${dir0}/reparse.awk"
}

## $1 - filter name
data_filter() {
	FILT="$*" "${dir0}/filter.awk"
}

## $1 - key
field_search() {
	printf '(%s[^,[:space:]]*(\s[^,]*)?|[^,]*\s%s[^,]*)' "$1" "$1"
}

## $1 - release/series
lookup() {
	grep -Ei '^'"$(field_search "$1")"'(,|$)'
}

## $1 - distro name
## $2 - release/series
query() {
	distro_known "$1" || return 1

	_query_r=''
	while : ; do
		if local_avail "$1" ; then
			_query_r=$(local_query "$1" "$2")
			if [ -n "${_query_r}" ] ; then break ; fi
		fi

		if remote_avail "$1" ; then
			_query_r=$(remote_query "$1" "$2")
			if [ -n "${_query_r}" ] ; then break ; fi
		fi

		unset _query_r
		return 1
	break ; done

	echo "${_query_r}"
	unset _query_r
}

if [ $# -eq 0 ] ; then exit 1 ; fi

q=$(mktemp)
case $# in
1) query "$1" | data_filter active ;;
*) query "$1" ;;
esac > "$q"

if ! [ -s "$q" ] ; then
	rm -f "$q" ; exit 1
fi

meta_ex() { cut -d ',' -f '1,2' ; }
tag_ex() { cut -d ',' -f 1 ; }
chan_ex() { cut -d ' ' -f 1 ; }

f_tags=$(mktemp)
d_chan=$(mktemp -d)

meta_ex < "$q" > "${f_tags}"

f_query="${d_chan}/query"

tag_ex < "${f_tags}" \
| chan_ex \
> "${f_query}"

filter_chan_ex() {
	data_filter "$2" < "$1" \
	| tag_ex \
	| chan_ex \
	> "$3"
}

a=$(mktemp) ; b=$(mktemp)
for s in stable testing lts ; do
	filter_chan_ex "$q" "$s" "${d_chan}/$s"

	grep -Fx  -f "${d_chan}/$s" < "${f_query}" > "$a"
	grep -Fxv -f "${d_chan}/$s" < "${f_query}" > "$b"

	cat < "$a" > "${d_chan}/$s"
	cat < "$b" > "${f_query}"
done
rm -rf "$a" "$b"

{
	for s in lts stable testing ; do
		while read -r c ; do
			lookup "$c" < "${f_tags}" \
			| sed -E 's/^(.+)$/\1,'"$s"'/'
		done < "${d_chan}/$s"
	done

	## Debian specific:
	## add tag 'unstable' to 'sid'
	if [ "$1" = 'debian' ] ; then
		lookup "sid" < "${f_tags}" \
		| sed -E 's/^(.+)$/\1,unstable/'
	fi

	## last resort
	while read -r c ; do
		lookup "$c" < "${f_tags}"
	done < "${f_query}"
} > "$q"

rm -rf "${f_tags}" "${d_chan}"

## secondary lookup (allows one to select release by meta tag)
shift
k=$(field_search "$1")
grep -Ei '^'"($k|[^,]+,[^,]+,$k)"'(,|$)' < "$q"
rm -rf "$q"

exit 0
