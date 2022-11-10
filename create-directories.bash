#!/usr/bin/env bash

set -o nounset            # Fail on use of unset variable.
set -o errexit            # Exit on command failure.
set -o pipefail           # Exit on failure of any command in a pipeline.
set -o errtrace           # Trap errors in functions and subshells.
set -o noglob             # Disable filename expansion (globbing),
                          # since it could otherwise happen during
                          # path splitting.
shopt -s inherit_errexit  # Inherit the errexit option status in subshells.

# Print a useful trace when an error occurs
trap 'echo Error when executing ${BASH_COMMAND} at line ${LINENO}! >&2' ERR

# Given a source directory, /source, and a target directory,
# /target/foo/bar/bazz, we want to "clone" the target structure
# from source into the target. Essentially, we want both
# /source/target/foo/bar/bazz and /target/foo/bar/bazz to exist
# on the filesystem. More concretely, we'd like to map
# /state/etc/ssh/example.key to /etc/ssh/example.key
#
# To achieve this, we split the target's path into parts -- target, foo,
# bar, bazz -- and iterate over them while accumulating the path
# (/target/, /target/foo/, /target/foo/bar, and so on); then, for each of
# these increasingly qualified paths we:
#   1. Ensure both /source/qualifiedPath and qualifiedPath exist
#   2. Copy the ownership of the source path to the target path
#   3. Copy the mode of the source path to the target path

initDir() {
    install -d ${mode:+--mode="$mode"} ${user:+--owner "$user"} ${group:+--group "$group"} "${1?}"
}

atomicDir() {
    local dir="$1"
    shift

    local cmd="$1"
    shift

    local parent
    parent="$(dirname "$dir")"

    if ! [[ -d "$parent" ]]; then
        initDir "$parent"
    fi

    # Create temporary directory in the parent directory of the target/final
    # directory; this helps ensure the final `mv -f` is an atomic rename (and
    # not, e.g., a cross-device copy).
    tmp="$(mktemp -d "${parent}/.$(basename "$dir").XXXXXXXXXX")"

    "$cmd" "$tmp" "$@" || {
        local rc="$?"
        rm -rf "${tmp?}"
        return "$rc"
    }

    # `-T` (`--no-target-directory`) to avoid copying `$tmp` into `$dir`,
    # should `$dir` have been created by something other than this run of this
    # function.
    mv -T -f "$tmp" "$dir"
}

permsFromReference() {
    chown --reference="${2?}" "${1?}"
    chmod --reference="${2?}" "${1?}"
}

atomicDirFromReference() {
    atomicDir "${1?}" permsFromReference "${2?}"
}

createDirs() {
    # Get inputs from command line arguments
    if [[ "$#" != 6 ]]; then
        printf "Error: 'create-directories.bash' requires *six* args.\n" >&2
        exit 1
    fi
    sourceBase="$1"
    target="$2"
    user="$3"
    group="$4"
    mode="$5"
    debug="$6"

    if (( debug )); then
        set -o xtrace
    fi

    # trim trailing slashes the root of all evil
    sourceBase="${sourceBase%/}"
    target="${target%/}"

    # check that the source exists and warn the user if it doesn't
    realSource="$(realpath -m "$sourceBase$target")"
    if [[ ! -d "$realSource" ]]; then
        printf "Warning: Source directory '%s' does not exist; it will be created for you with the following permissions: owner: '%s:%s', mode: '%s'.\n" "$realSource" "$user" "$group" "$mode"
    fi

    # iterate over each part of the target path, e.g. var, lib, iwd
    previousPath="/"

    OLD_IFS=$IFS
    IFS=/ # split the path on /
    for pathPart in $target; do
        IFS=$OLD_IFS

        # skip empty parts caused by the prefix slash and multiple
        # consecutive slashes
        [[ "$pathPart" == "" ]] && continue

        # construct the incremental path, e.g. /var, /var/lib, /var/lib/iwd
        currentTargetPath="$previousPath$pathPart/"

        # construct the source path, e.g. /state/var, /state/var/lib, ...
        currentSourcePath="$sourceBase$currentTargetPath"

        # create the source and target directories if they don't exist
        if [[ ! -d "$currentSourcePath" ]]; then
            initDir "$currentSourcePath"
        fi

        # resolve the source path to avoid symlinks
        currentRealSourcePath="$(realpath -m "$currentSourcePath")"

        if [[ -d "$currentTargetPath" ]]; then
            # synchronize perms between source and target
            permsFromReference "$currentTargetPath" "$currentRealSourcePath"
        else
            # create target directory with perms from source
            atomicDirFromReference "$currentTargetPath" "$currentRealSourcePath"
        fi

        # lastly we update the previousPath to continue down the tree
        previousPath="$currentTargetPath"
    done
}

# if `return 0` succeeds, this script is being sourced
if ! (return 0) &>/dev/null; then
    createDirs "$@"
fi
