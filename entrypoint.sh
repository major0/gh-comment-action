#!/bin/sh
set -e
set --

die() { echo "error: $*" >&2; exit 1; }
lower() { printf '%s' "${*}"|tr '[:upper:]' '[:lower:]'; }
upper() { printf '%s' "${*}"|tr '[:lower:]' '[:upper:]'; }

case "$(lower "${INPUT_DEBUG:=false}")" in
(yes|true|1)
	printf '##\n# Args: %s\n#Environ: %s' "${*}" "$(env | grep '^GITHUB_' | sort)"
	set -- --trace
	set -x
	;;
esac

test -f "${INPUT_TEMPLATE}" || die "no such file '${INPUT_TEMPLATE}'"

ARTIFACT_LIST="$(printf '%s' "${INPUT_ARTIFACTS}" | while read -r LINE; do printf '%s ' "${LINE}";done)"
for artifact_id in ${ARTIFACT_LIST}; do
	set -- "${@}" --artifacdt "${artifact_id}"
done

: ./gh-issue-comment.sh "${@}" "${INPUT_TEMPLATE}" "${INPUT_ID}"
