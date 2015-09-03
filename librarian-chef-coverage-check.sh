#! /bin/bash

function die() {
	local msg="${*}"
	[[ -n "${msg:-}" ]] && echo >&2 -e "FATAL: ${msg}"
	exit 1
} # die

function main() {
	local -i rc=0

	while read -r CB; do
		# Skip (previously) broken cookbook...
		#[[ "${CB}" == "proxy" ]] && continue

		grep -i --colour=always "^\s*cookbook\s\+['\"]${CB}['\"]\s*,\?\s*$" Cheffile || {
			echo "Missing: '${CB}'"
			rc=1
		}
	done < <(
		{
			  grep "depends ['\"]" cookbooks/*/metadata.rb	\
			| sed "s/\"/'/g"				\
			| cut -d"'" -f 2
			  ls -1d cookbooks/*				\
			| sed 's|^cookbooks/||'
		}							\
		| sort							\
		| uniq
	)

	return ${rc}
} # main

cd "$( dirname "$( readlink -e "${0}" )" )" || die "Cannot chdir() to script directory '$( dirname "${0}" )': ${?}"
[[ -d cookbooks ]] || die "Cannot locate '${PWD:+${PWD}/}cookbooks' directory"
[[ -s Cheffile && -r Cheffile ]] || die "Cannot locate readable librarian-chef 'Cheffile' manifest"

main

exit ${?}
