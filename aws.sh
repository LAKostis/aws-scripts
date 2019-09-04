#!/bin/sh -efu

. shell-error
. shell-quote
. shell-args
. shell-ini-config

PROG="${0##*/}"
PROG_VERSION='0.1'

aws=/usr/local/bin/aws
short=
json=
profile=
cmd=
version=latest

[ -x "$aws" ] || fatal "aws binary not found on $aws location"

show_help() {
	cat <<EOF
Usage: Usage: $PROG -p <profile> [options] <cmd>

Options:

  -p, --profile=<name>          AWS profile name;
  -V, --version                 print program version and exit;
  -h, --help                    show this text and exit;
  -j, --json                    use json output.

Command shortcuts:

list-iam-users
list-iam-roles
list-iam-policies
list-iam-groups
list-role-policies

get-user <user> [full]
get-role <role> [full]
get-policy <policy> [version]

Advanced usage:

$PROG [options] -- <aws direct cmd>

EOF
	exit
}

print_version() {
	cat <<EOF
$PROG version $PROG_VERSION
Written by Konstantin Lepikhov <konstantin@tiqets.com>

This is free software; see the source for copying conditions.  There is NO
warranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
EOF
	exit
}

get_user_arn() {
	local user="$1"
	shift
	"$aws" iam get-user --user-name "$user" | jq -r '.User.Arn'
}

get_policy_arn() {
	local policy="$1"
	shift
	"$aws" iam list-policies | jq -r ".Policies[]|if .PolicyName == \"$policy\" then .Arn else empty end"
}

get_default_policy_version() {
	local policy="$1"
	shift
	"$aws" iam list-policies | jq -r ".Policies[]|if .PolicyName == \"$policy\" then .DefaultVersionId else empty end"
}

list_policy() {
	local policy="$1"
	shift
	local version="$1"
	shift
	local arn="$(get_policy_arn $policy)"
	"$aws" iam get-policy --policy-arn "$arn"
	"$aws" iam list-entities-for-policy --policy-arn "$arn"
	[ "$version" == 'latest' ] && version="$(get_default_policy_version $policy)"
	"$aws" iam get-policy-version --policy-arn "$arn" --version-id "$version"
}

list_policies() {
	local role="$1"
	shift
	echo "Listing inline policies:"
	"$aws" iam list-role-policies --role-name "$role"
	echo "Listing attached policies:"
	"$aws" iam list-attached-role-policies --role-name "$role"
}

list_users() {
	local users="$1"
	shift
	for user in $users; do
		"$aws" iam list-attached-user-policies --user-name "$user"
		"$aws" iam list-user-policies --user-name "$user"
		"$aws" iam list-groups-for-user --user-name "$user" | jq -r '.Groups[]|{ GroupName, Arn }'
	done
}

TEMP=$(getopt -n $PROG -o 'p:,h,V,j' -l 'profile:,help,version,json' -- "$@") ||
	show_usage
eval set -- "$TEMP"

while :; do
	case "$1" in
	-p | --profile)
		shift
		profile="$1"
		;;
	-h | --help)
		show_help
		;;
	-V | --version)
		print_version
		;;
	-j | --json)
		json=1
		;;
	--)
		shift
		break
		;;
	esac
	shift
done

[ -n "$profile" ] || show_usage

export AWS_PROFILE="$profile"

cmd="$1"
shift

case "$cmd" in
list-iam-users)
	cmd='iam list-users'
	short='.Users[].UserName'
	list_users "$(eval $aws $cmd | jq -r $short)"
	exit $?
	;;
list-iam-roles)
	cmd='iam list-roles'
	short='.Roles[].RoleName'
	;;
list-iam-policies)
	cmd='iam list-policies --scope=Local'
	short='.Policies[].PolicyName'
	;;
list-iam-groups)
	cmd='iam list-groups'
	short='.Groups[].GroupName'
	;;
list-role-policies)
	role="$1"
	shift
	list_policies "$role"
	exit $?
	;;
get-*)
	param="$1"
	shift
	arg="${cmd##get-}"
	[ "$#" -gt 0 ] && version="$1"
	if [ "$arg" = 'policy' ]; then
		list_policy "$param" "$version"
		exit $?
	fi
	cmd="iam $cmd --$arg-name $param"
	eval "$aws" "$cmd"
	if [ "$#" -gt 0 ]; then
		case "$1" in
		full)
			[ "$arg" = 'role' ] && list_policies "$param"
			[ "$arg" = 'user' ] && list_users "$param"
			;;
		esac
	fi
	exit $?
	;;
*)
	fatal "$cmd: Unsupported!"
	;;
esac

if [ "$#" -eq 0 ]; then
	[ -n "$json" ] && eval "$aws" "$cmd" || eval "$aws" "$cmd" | jq -r "${short:-}"
else
	$aws "$cmd" "$*"
fi
