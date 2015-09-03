#!/bin/bash

# Interrogate cookbooks and report outdated instances
#
# Authored: Stuart Shelton [SRCS] 20140124
#

# stdlib.sh should be in /usr/local/lib/stdlib.sh, which can be found as
# follows by scripts located in /usr/local/{,s}bin/...
std_LIB="stdlib.sh"
for std_LIBPATH in \
	"." \
	"$( dirname "$( type -pf "${std_LIB}" 2>/dev/null )" )" \
	"$( readlink -e "$( dirname "${0:-.}" )/../lib" )" \
	"/usr/local/lib"
do
	if [[ -r "${std_LIBPATH}/${std_LIB}" ]]; then
		break
	fi
done
# shellcheck disable=SC1091
# shellcheck source=https://raw.githubusercontent.com/srcshelton/stdlib.sh/master/stdlib.sh
[[ -r "${std_LIBPATH}/${std_LIB}" ]] && source "${std_LIBPATH}/${std_LIB}" #|| {
#        echo >&2 "FATAL:  Unable to source ${std_LIB} functions"
#        exit 1
#}

# Be safe, now...
set -u

# Ensure we get the *real* exit-status from pipelines...
set -o pipefail

# Ensure that we have basic functions, in case stdlib.sh is missing
if [[ "$( type -t die )" != "function" ]]; then
	function die() {
		echo >&2 "FATAL: ${*:-}"
		exit 1
	}
fi
if [[ "$( type -t warn )" != "function" ]]; then
	function warn() {
		echo >&2 "WARN:  ${*:-}"
	}
fi
if [[ "$( type -t info )" != "function" ]]; then
	function warn() {
		echo "INFO:  ${*:-}"
	}
fi
if [[ "$( type -t debug )" != "function" ]]; then
	function debug() {
		(( std_DEBUG )) && echo "DEBUG: ${*:-}"
		return $(( !( std_DEBUG ) ))
	}
fi

std_DEBUG="${DEBUG:-0}"
std_TRACE="${TRACE:-0}"

(( std_TRACE )) && set -o xtrace

supermarketapi="https://supermarket.getchef.com/api/v1/cookbooks/"
giturl="https://raw.github.com/opscode-cookbooks"

function main() {
	cd "$( dirname "${0}" )" || \
		die "chdir() to '$( dirname "${0}" )' failed: ${?}"
	[[ -d cookbooks ]] && {
		cd cookbooks || \
			die "chdir() to '$( dirname "${0}" )/cookbooks' failed: ${?}"
	}

	type -pf curl >/dev/null 2>&1 || \
		die "Cannot locate 'curl' binary in \$PATH"
	echo -e "1.2\n1.1" | sort -V >/dev/null 2>&1 || \
		die "'sort' binary lacks version-sort ability:" \
		    "please upgrade coreutils"

	[[ -n "${std_LIBPATH:-}" ]] && debug "std_LIBPATH is '${std_LIBPATH}'"
	debug " "

	local dir maintainer email vlocal vremote ncm repo name url major minor
	local latest tempfile
	std::emktemp tempfile "${$}" || die "std::emktemp failed: ${?}"

	for dir in $(
		  find . -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
		| sed 's|^\./||'
	); do
		if ! [[ -s "${dir}"/metadata.rb ]]; then
			debug "Directory '${dir}' lacks file 'metadata.rb'"
			continue
		else
			# For the next two extractions, we were going to use simply:
			#   cut -d'"' -f 2
			# ... but some (actually one, for 'ntp') metadata.rb files use
			# single quotes rather than double quotes.  This leads to parsing
			# issues, and the need to do this :(
			#
			name="$(
				  grep -Em 1 '^name\s' \
				             "${dir}"/metadata.rb \
				| sed -r 's/^.*["]([^"]+)["]/\1/' \
				| sed -r "s/^.*[']([^']+)[']/\1/"
			)"
			maintainer="$(
				  grep -Em 1 '^maintainer\s' \
				             "${dir}"/metadata.rb \
				| sed -r 's/^.*["]([^"]+)["]/\1/' \
				| sed -r "s/^.*[']([^']+)[']/\1/"
			)"
			email="$(
				  grep -Em 1 '^maintainer_email\s' \
				             "${dir}"/metadata.rb \
				| sed -r 's/^.*["]([^"]+)["]/\1/' \
				| sed -r "s/^.*[']([^']+)[']/\1/"
			)"
			vlocal="$(
				  grep -Em 1 '^version\s' \
				             "${dir}"/metadata.rb \
				| sed -r 's/^.*["]([^"]+)["]/\1/' \
				| sed -r "s/^.*[']([^']+)[']/\1/"
			)"

			[[ -n "${maintainer:-}" ]] || {
				warn "Cookbook '${name:-${dir}}' lacks maintainer" \
				     "data in 'metadata.rb'" # , skipping"
				     #continue
			}
			[[ -n "${vlocal:-}" ]] || {
				warn "Cookbook '${name:-${dir}}' lacks version data" \
				     "in 'metadata.rb'" #, skipping"
				#continue
			}
			debug "Read version '${vlocal:-}', maintainer" \
			      "'${maintainer:-}'(${email:-<no email>}) for Cookbook" \
			      "'${name:-${dir}}' ..."

			ncm="$( shopt -q nocasematch ; echo $? ; )"
			# We actually want fall-through behaviour here...
			# shellcheck disable=SC2015
			(( ncm )) && shopt -s nocasematch || unset ncm
			if [[ -z "${maintainer:-}" ]]; then
				[[ -n "${ncm:-}" ]] && shopt -u nocasematch
				unset ncm

				debug "Cookbook '${name:-${dir}}' is unmaintained - skipping"
				continue

			else
				[[ -n "${ncm:-}" ]] && shopt -u nocasematch
				unset ncm

				# Let's try the Supermarket API first...
				curl "${CURLOPTS[@]:-}" "${supermarketapi}/${name:-${dir}}" \
					| sed -r 's/,/,\n/g ; s/([\[{])/\1\n/g ; s/(}|\])/\n\1/g' \
					> "${tempfile}" || \
				{
					error "curl failed fetching URL" \
					      "'${supermarketapi}/${name:-${dir}}': ${?}"
					continue
				}
					
				if grep -q '^"error_code":"NOT_FOUND"$' "${tempfile}"; then
						warn "Cookbook '${name:-${dir}}' is not known by the" \
						     "Opscode API"
				else
					grep -q '^"deprecated":true,$' "${tempfile}" && \
						warn "Cookbook '${name:-${dir}}' is now deprecated"
					vremote="$(
						grep -A 2 '^"versions":\[$' "${tempfile}" \
							| tail -n +2 \
							| grep -Eo '/versions/.*",?$' \
							| cut -d'/' -f 3- \
							| cut -d'"' -f 1 \
							| while read -r vremote
						do
							minor="$( sed 's/^.*\.//' <<<"${vremote}" )"
							debug "Read minor version '${minor}' from remote" \
							      "version '${vremote}'"
							if (( 0 != ( minor % 2 ) )); then
								debug "Remote version '${vremote}' is a" \
								      "development version, disregarding..."
							else
								debug "Cookbook ${name:-${dir}} has local" \
								      "version '${vlocal}', remote version" \
									  "'${vremote}'"
								respond "${vremote}"
								break
							fi
						done
					)"
					debug "vremote is ${vremote:-}"
				fi
			fi

			if [[ -z "${vremote:-}" ]]; then
				ncm="$( shopt -q nocasematch ; echo $? ; )"
				# We actually want fall-through behaviour here also...
				# shellcheck disable=SC2015
				(( ncm )) && shopt -s nocasematch || unset ncm
				if ! [[ \
					"${maintainer}" =~ opscode.* || \
					"${maintainer}" == "Chef" \
				]]; then
					[[ -n "${ncm:-}" ]] && shopt -u nocasematch
					unset ncm

					# TODO: Check for other origins here
					debug "Cookbook '${name:-${dir}}' is not from Opscode" \
						  "and lacks source-link, unable to check" \
						  "versions"
				else
					[[ -n "${ncm}" ]] && shopt -u nocasematch
					unset ncm

					repo="${dir#ops-}"
					repo="${repo#iod-}"
					repo="${repo#ref-}"
					repo="${repo#latest-}"
					repo="${repo%-[0-9]*}"
					[[ "${repo}" == "${dir}" ]] \
						&& name="'${dir}'" \
						|| name="'${dir}'(${repo})"
					url="${giturl}/${repo}/master/metadata.rb"
					debug "Fetching URL '${url}' ..."
					vremote="$(
						  curl "${CURLOPTS[@]:-}" "${url}" 2>&1 \
						| grep -Em 1 '^version\s' \
						| sed -r 's/^.*["]([^"]+)["]/\1/' \
						| sed -r "s/^.*[']([^']+)[']/\1/"
					)"
					[[ -n "${vremote}" ]] || {
						warn "Cannot read remote version for cookbook" \
							 "${name} from URL '${url}'"
						continue
					}

					# FIXME: We need to deal with major/minor/dev tripples
					# here...
					debug "Cookbook ${name} has local version '${vlocal}'," \
						  "remote version '${vremote}'"
					major="$( sed 's/\.[^.]\+$//' <<<"${vremote}" )"
					minor="$( sed 's/^.*\.//' <<<"${vremote}" )"
					if (( 0 != ( minor % 2 ) )); then
						(( minor -- ))
						(( minor < 0 )) && minor=0
						debug "Remote version '${vremote}' is a development" \
							  "version, decrementing to '${major}.${minor}'"
						vremote="${major}.${minor}"
					fi
				fi
			fi

			if [[ -z "${vremote:-}" ]]; then
				error "Could not retrieve remote version for cookbook" \
					"'${name:-${dir}}'"
				(( std_DEBUG )) && \
					debug "Supermarket API data was:\n$( < "${tempfile}" )"
			else
				if [[ \
					"${vremote}" == "${vlocal}" || \
					"${vremote}" =~ ^${vlocal}\. \
				]]; then
					debug "Versions match for cookbook ${name:-${dir}}"
				else
					if (( std_DEBUG )); then
						output "Sort results are:"
						echo -e "${vlocal}\n${vremote}" | sort -V
					fi
					latest="$(
						  echo -e "${vlocal}\n${vremote}" \
						| sort -V 2>/dev/null \
						| tail -n 1
					)"
					if [[ "${latest}" == "${vlocal}" ]]; then
						warn "Cookbook ${name:-${dir}} is more recent with" \
							 "version '${vlocal}' than stable version" \
							 "'${vremote}'"
					else
						warn "Cookbook ${name:-${dir}} is out-dated with" \
							 "version '${vlocal}', version '${vremote}' is" \
							 "available"
					fi
				fi
			fi
		fi
		debug " "
		vremote=""
		name=""
	done
} # main

declare -a CURLOPTS=( "-Ls" )

main "${@:-}"

exit 0

# set vi: syntax=sh ts=4 colorcolumn=80 foldmethod=marker:
