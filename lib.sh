#!/usr/bin/env bash

# Support library for tools

## error [message]..
##
## Pretty print error messages
error() {
  echo $'\e[31merror\e[m:' "${BASH_SOURCE[1]}(${BASH_LINENO[1]}) ${FUNCNAME[1]}: " "$@" >&2
}

## os
##
## Print the OS name in lower case.
os() {
  if [[ $OS == Windows_NT ]]; then
    echo windows
  else
    os=$(uname)
    echo "${os,,}"
  fi
}

## arch_from_triple <triple>
##
## Print architecture from a target triplet.
arch_from_triple() {
  local triple=$1
  echo "${triple%%-*}"
}

## ncpu
##
## Print number of logical CPUs, 1 is printed if couldn't be found
ncpu() {
  local ncpu=
  case "$(os)" in
    windows)
      ncpu=$NUMBER_OF_PROCESSORS
      ;;
    darwin)
      ncpu=$(sysctl -n hw.ncpu)
      ;;
    linux)
      ncpu=$(nproc)
      ;;
  esac
  if [[ $ncpu -le 0 ]]; then
    ncpu=1
  fi

  echo "$ncpu"
}

## nativepath <path>
##
## Translate the given unix path to a native path.
nativepath() {
  if [[ $# -eq 0 ]]; then
    error "a path must be given"
    return 1
  fi
  if [[ -z "$1" ]]; then
    error "path must not be empty"
    return 1
  fi
  case "$(os)" in
    windows)
      echo "${1/\//\\}"
      ;;
    *)
      echo "$1"
      ;;
  esac
}

## pushenv (<variable name> [<value>])..
##
## Push the specified environment variable to be used with the next step in a
## job pipeline.
pushenv() {
  if [[ $# -eq 0 ]]; then
    error "a variable name must be passed"
    return 1
  fi

  local printNotice=true
  while [[ $# -gt 0 ]]; do
    local name=$1
    local value=$2

    if [[ $value == *$'\n'* ]]; then
      error "variable value must not contain newline"
      return 1
    fi
    if [[ -v GITHUB_ACTIONS ]]; then
      echo "::set-env name=$name::$value"
    else
      if $printNotice; then
        echo "Environmental settings are appended to $PWD/environment"
        printNotice=false
      fi
      echo "export $name=${value@Q}" >> environment
    fi

    shift 2 || shift $#
  done
}

## pushpath <path>..
##
## prepend the given values to PATH for the next step in a job pipeline.
pushpath() {
  if [[ $# -eq 0 ]]; then
    error "a path must be passed"
    return 1
  fi

  declare -a _pushpath_path
  local snippet=false
  while [[ $# -gt 0 ]]; do
    if [[ -z "$1" ]]; then
      error "path must not be empty"
      return 1
    fi
    local path
    path=$(nativepath "$(realpath "$1")")
    if [[ $1 == *$'\n'* ]]; then
      error "variable value must not contain newline"
      return 1
    fi
    if [[ -v GITHUB_ACTIONS ]]; then
      echo "::add-path::$path"
    else
      snippet=true
      _pushpath_path=( "$path" "${_pushpath_path[@]}" )
    fi

    shift 1
  done

  if $snippet; then
    echo "Environmental settings are appended to $PWD/environment"
    (IFS=': '; echo "export PATH=${_pushpath_path[*]@Q}\"\${PATH:+:\$PATH}\"") >> environment
  fi
}

## fold [desc]..
##
## Start output fold with description `desc`
fold() {
  if [[ -v GITHUB_ACTIONS ]]; then
    echo "::group::$*"
  fi
}

## endfold
##
## End the last output fold
endfold() {
  if [[ -v GITHUB_ACTIONS ]]; then
    echo "::endgroup::"
  fi
}
