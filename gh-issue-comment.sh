#!/bin/sh

set -e

error() { echo "error: $*"; }
die() { echo "error: $*"; exit 1;}
lower() { printf '%s' "${*}" | tr '[:lower:]'; }
upper() { printf '%s' "${*}" | tr '[:upper:]'; }
count() { jq 'def count(s): reduce s as $_ (0;.+1); count(.[])'; }
gh_event() { jq -r "$*" < "${GITHUB_EVENT_PATH}"; }

# FIXME not certain how `gh auth status` knows the current user but
# `gh api user` does not...
__gh_auth_id()
{
	set -- "$(gh auth status 2>&1 | sed -E -n 's/.*Logged in to [^[:space:]]+ as ([^[:space:]]+) \(.*\)/\1/p')"
	: '__gh_auth_status:'
	: "$(gh auth status)"
	: "__gh_auth_login='${1}'"
	echo "${1}"
}
gh_user() { gh api "users/$(__gh_auth_id)" --jq '.login'; }
gh_uid() { gh api "users/$(__gh_auth_id)" --jq '.id'; }

comment_link()
{
	printf '[gh_comment_id]: %s@%s\n' "$(printf '%s:%s' "$(gh_uid)" "${1}" | sha256sum | awk '{print$1}')" "${2}"
}
artifact_links()
{
	artifact_ids="${1}"
	set --
	while test -n "${artifact_ids}"; do
		artifact_id="${artifact_ids%% *}"
		artifact_name="${artifact_id%@*}"
		artifact_run_id="${artifact_id#*@}"
		artifact_ids="${artifact_ids#${artifact_id}}"
		artifact_ids="${artifact_ids## }"

		# Avoid duplicating links
		for artifact_seen; do test "${artifact_seen}" != "${artifact_id}" || continue 2; done

		artifact_run_data="$(gh api "repos/{owner}/{repo}/actions/runs/${artifact_run_id}/artifacts" --jq '.artifacts')"

		if test "$(lower "${artifact_name}")" = 'all'; then
			for entry in $(printf '%s' "${artifact_run_data}" | jq -r '.artifacts[].name'); do
				artifact_links "${entry}@${artifact_run_id}"
				# Mark each artifact as seen
				set -- "${@}" "${entry}@${artifact_run_id}"
			done
		else
			artifact_query="$(printf '.artifacts[] | select(.name == "%s")' "${artifact_name}")"
			artifact_data="$(printf '%s' "${artifact_data}" | jq -r "${artifact_query}")"
			if test -z "${artifact_data}"; then
				echo "ERROR: no data for '${artifact_name}' in run ${artifact_run_id}"
			else
				printf '| [%s](%s) | %s | %s |' \
					"$(printf '%s' "${artifact_data}" | jq '.name')" \
					"$(printf '%s' "${artifact_data}" | jq '.archive_download_url')" \
					"$(printf '%s' "${artifact_data}" | jq '.expires_at')" \
					"$(printf '%s' "${artifact_data}" | jq '.size_in_bytes')"
			fi
		fi

		# Mark this pattern as seen, including `all`, as seen
		set -- "${@}" "${artifact_id}"
	done
}
usage()
{
	if test "$#" -gt '0'; then
		error "$*"
		echo "try '$0 --help'"
		exit 1
	fi

	sed -e 's/^	//'<<END_OF_USAGE
	usage: $0 [options] <FILE> [<ISSUE>|<PR>]
	  Post the body of the supplied FILE as a comment to the specified ISSUE/PR number.

	options:
	  -c ID			Specify a comment tracking id.  This is a unique string used to keep track of
	  --comment-id		the comment when updating posts.

	  -a NAME@ID		Add links to named artifact found in run ID to the end of the posted comment.
	  --artifact NAME@ID	Can be specified more than once. If 'all' is suppled as the NAME then add
	                        links for all artifacts found in run ID.

	  -x, --trace		Enable execution tracing.

	  -h, --help		Display this help.

END_OF_USAGE

	# requests for help are never an error
	exit 0
}

ISSUE_ID=
COMMENT_ID=
ARTIFACT_IDS=
DRY_RUN='false'
while test "$#" -gt '0'; do
	case "$1" in
	(-c|--comment-id)	COMMENT_ID="${2}"; shift;;
	(-a|--artifact)		ARTIFACT_IDS="${2}"; shift;;
	(-n|--try-run)		DRY_RUN='true';;
	(-x|--trace)		set -x;;
	(-h|--help)		usage;;

	# Let's be a little POSIX'ish
	(--)			shift; break;;
	(-*)			usage "unknown option '$1'";;
	(*)			break;;
	esac
	shift
done

gh version > /dev/null 2>&1 || die 'required gh cli tool not found'

test "$#" -gt '0' || die 'no markdown document specified'
test "$#" -gt '1' || die 'no issue/pull-request number specified'
test "$#" -eq '2' || die "unknown argument '${3}'"

test -e "${1}" || die "does not exist '${1}'"
test -f "${1}" || die "not a file '${1}'"

ISSUE_ID="${2}"

if test -n "${COMMENT_ID}"; then
	COMMENT_ID="$(gh_uid):${COMMENT_ID}"
else
	COMMENT_ID="$(gh_uid)"
fi
COMMENT_LINK="$(comment_link "${COMMENT_ID}" "${ISSUE_ID}")"

TMP_COMMENT='/tmp/gh-issue-comment.md'
cleanup() { rm -f "${TMP_COMMENT}"; }
trap cleanup 0 EXIT
cat "${1}" > "${TMP_COMMENT}"

if test -n "${ARTIFACT_IDS}";then
	sed -e 's/^	//'>>"${TMP_COMMENT}"<<END_OF_COMMENT

	| Artifact Name | Expiration Date | Size |
	|:--------------|:---------------:|-----:|
	$(artifact_links "${ARTIFACT_IDS}")
END_OF_COMMENT
fi

printf '\n%s\n' "${COMMENT_LINK}" >> "${TMP_COMMENT}"

comment_query="$(printf '.[] | select((.user.id = %s) and (.body | contains("%s")))' "$(gh_uid)" "${COMMENT_LINK}")"
comment="$(gh api "repos/{owner}/{repo}/issues/${ISSUE_ID}/comments" --jq "${comment_query}")"
echo "::set-output comment=${comment}"
if test -z "${comment}"; then
	"${DRY_RUN}" || gh api "repos/{owner}/{repo}/issues/${ISSUE_ID}/comments" --field "body=@${TMP_COMMENT}"
else
	comment_id="$(printf '%s' "${comment}" | jq '.id')"
	"${DRY_RUN}" || gh api --method PATCH "repos/{owner}/{repo}/issues/comments/${comment_id}" --field "body=@${TMP_COMMENT}"
fi
