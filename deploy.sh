#!/usr/bin/env bash
#
# Tools for deploying our release to github
#
# Usage: ./deploy.sh [--debug] deploy [--no-upload] [-n] [-r REMOTE_REPOS] [--replace] [-u GITHUB_USER] [RELEASE_VERSION]
#        ./deploy.sh [--debug] build [RELEASE_VERSION]
#        ./deploy.sh [--debug] delete RELEASE_VERSION
#        ./deploy.sh [--debug] init [-i]
#
# Description:
#   deploy.sh is a wrapper arroung github-release to build and deploy a github release through
#   github API.
#
# Options:
#   -n                   Dry run, show with version, files and description.
#   -r REMOTE_REPOS      Specify a REMOTE_REPOS name [default: origin]
#   --replace            Replace existing release with this one, previous release
#                        will be deleted first.
#   -u GITHUB_USER       force this GITHUB_USER.
#   --debug              output debug information.
#   -i                   Ingore existing file during init. Template are skipped.
#   --no-upload          Don't perform binaries upload (test for speedup).
#
# Arguments:
#   RELEASE_VERSION      a git tag, or current for the local modified version
#
# Actions:
#   build      only build using gox and deployment.yml config
#   deploy     prepare and deploy the release
#   delete     delete the given RELEASE_VERSION from github and all assets
#   init       initilise deploy.sh environment and create deployment.yml
#
# deploy.sh reads description and name for releases in deployment.yml

# ^^^  keep empty line above for docopts.sh parsing ^^^

# ============================================================ GLOBALS

DEPLOYMENT_FILE=deployment.yml
# change GITHUB_USER + GITHUB_REPO to change repository, it is for building API URL
# var can be exported from your env
GITHUB_USER=${GITHUB_USER:-empty}
GITHUB_REPO=${GITHUB_REPO:-empty}
TAG="$(cat VERSION)"
BUILD_DEST_DIR=build
TMP_DIR=/tmp
# RELEASE_LDFLAGS will be added to -ldflags
# See: go tool link -h
# -s
#  Omit the symbol table and debug information
# -w
#  Omit the DWARF symbol table.
RELEASE_LDFLAGS="-s -w"

# ====================================================================== helpers
fail()
{
  error "${BASH_SOURCE[1]}:${FUNCNAME[1]}:${BASH_LINENO[0]}: $*"
  exit 1
}

error()
{
  # write on stderr
  >&2 echo "error: $*"
}

# non maskable output (bats stderr kept on $output)
debug()
{
  if [[ $DEBUG -eq 1 ]] ; then
    # write on non standar non stdout non stderr descriptor
    echo "[tty]debug: $*" > /dev/tty
  fi
}

# stop_script is the main function which kill INT (Ctrl-C) your script
# it doesn't exit because you can source it too.
# you don't have to call this function unless you extend some fail_if function
stop_script()
{
  # test whether we are in interactive shell or not
  if [[ $- == *i* ]]
  then
    # autokill INT myself = STOP
    kill -INT $$
  else
    exit $1
  fi
}

fail_if_dir_not_exists()
{
  local d=$1
  if [[ ! -d "$d" ]] ; then
    error "folder not found: '$d' at ${BASH_SOURCE[1]}:${FUNCNAME[1]} line ${BASH_LINENO[0]}"
    stop_script 3
  fi
}

fail_if_file_not_exists()
{
  local f=$1
  if [[ ! -f "$f" ]] ; then
    error "file not found: '$f' at ${BASH_SOURCE[1]}:${FUNCNAME[1]} line ${BASH_LINENO[0]}"
    stop_script 3
  fi
}

fail_if_empty()
{
  local varname
  local v
  # allow multiple check on the same line
  for varname in $*
  do
    eval "v=\$$varname"
    if [[ -z "$v" ]] ; then
      error "$varname empty or unset at ${BASH_SOURCE[1]}:${FUNCNAME[1]} line ${BASH_LINENO[0]}"
      stop_script 4
    fi
  done
}

#====================================================================== functions

create_release()
{
  local release="$1"
  local name="$2"
  local description="$3"

  # detect alpha ==> pre-release
  # match -ending
  local pre_release=""
  if [[ $release =~ -[a-zA-Z0-9_-]$ ]] ; then
    pre_release='--pre-release'
  fi

  github-release release \
      --user $GITHUB_USER \
      --repo $GITHUB_REPO \
      --tag "$release" \
      --name "$name" \
      --description "$description" \
      $pre_release
}

# check the the given release exists, test with $?
check_release()
{
  local release=$1
  github-release info \
      --user $GITHUB_USER \
      --repo $GITHUB_REPO \
      --tag "$release" > /dev/null 2>&1
}

delete_release()
{
  local release=$1
  github-release delete \
      --user $GITHUB_USER \
      --repo $GITHUB_REPO \
      --tag "$release"
}

# after build, generate sha256sum for all file in $BUILD_DEST_DIR
# then output all files name from parent directory
prepare_upload()
{
  local build_dest_dir=$1
  pushd $build_dest_dir > /dev/null
  # cleanup
  rm -f sha256sum.txt
  sha256sum * > sha256sum.txt
  popd > /dev/null
  find $build_dest_dir -type f -a ! -name .\*
}

# perform the upload to github using github-release
# which can be very slow
upload_binaries()
{
  local release=$1
  shift
  local filenames=$*

  local f
  for f in $filenames
  do
    echo "uploading '$f' ..."
    github-release upload \
        --user $GITHUB_USER \
        --repo $GITHUB_REPO \
        --tag "$release" \
        --name "$(basename $f)" \
        --file "$f" \
        --replace
  done
}

indent()
{
  local arg="$1"
  if [[ -f "$arg" ]] ; then
    sed -e 's/^/  /' "$arg"
  else
    sed -e 's/^/  /' <<< "$arg"
  fi
}

# read os/arch from $DEPLOYMENT_FILE
# format as list or space separated list for gox
get_arch_build_target()
{
  local arch_list=$(yq.v2 r $DEPLOYMENT_FILE build | sed -e 's/^- //')
  if [[ $# -eq 1 && $1 == 'gox' ]] ; then
    # join output and trim
    tr $'\n' ' ' <<< "$arch_list" | sed -e 's/ $//'
  else
    echo "$arch_list"
  fi
}

# copy all current project to a folder
# if $dest_dir is a sub-folder it is excluded
# NOT USED
sync_src_to()
{
  local dest_dir=${1%/}
  fail_if_dir_not_exists $dest_dir
  rsync -a \
    --exclude=$dest_dir \
    --exclude=.git \
    --exclude=.*.swp \
    --exclude=.*.swo \
    ./ $dest_dir/
}

build_binaries()
{
  local release=$1
  local build_dest_dir=${2%/}
  local target=$3

  local ldflags
  local tmp_git_archive=""

  # convert build_dest_dir to fullpath
  build_dest_dir=$(realpath $build_dest_dir)

  # ldflags are synchronised with Makefile through ./get_ldflags.sh
  # current is an alias for using the current code not a tag
  if [[ $release == current ]] ; then
    # will use ./VERSION to get the version and use current uncommited code

    # ldflags are read in the source directory
    # govvv will fail if .git is missing
    ldflags="$(./get_ldflags.sh)"
  else
    # checkout a release version to $TMP_DIR and we will build it from here

    # we force the version to be $release.
    echo "extracting git release $release..."
    local extract_dir="${target}_$release.$$"
    git archive --format=tar --prefix="$extract_dir/" $release | (cd $TMP_DIR && tar xf -)
    tmp_git_archive="$TMP_DIR/$extract_dir"

    ldflags="$(./get_ldflags.sh "$(govvv -flags -version "$release")")"
  fi

  local osarch="$(get_arch_build_target gox)"
  ldflags="$RELEASE_LDFLAGS $ldflags"
  # -output allow to force generated binaries format and destination
  local cmd="gox -osarch \"$osarch\" -output=\"${build_dest_dir}/${target}_{{.OS}}_{{.Arch}}\" -ldflags \"$ldflags\""
  #echo "$cmd"
  if [[ -d "$tmp_git_archive" ]] ; then
    pushd "$tmp_git_archive" > /dev/null
    eval "$cmd"
    popd > /dev/null
    rm -rf "$tmp_git_archive"
  else
    # from the current directory
    eval "$cmd"
  fi
}

# fetch all yaml subkeys from the given file.yml from key KEY
# Call: yaml_keys FILE_YAML KEY
yaml_keys()
{
  # yq seems to young software, quick fix to get keys
  # https://github.com/mikefarah/yq/issues/20
  yq.v2 r "$1" "$2" | sed -n -e '/^\([^ ]\([^:]\+\)\?\):/  s/:.*// p'
}

show_release_data()
{
  local release=$1
  local name="$2"
  local description="$3"

  local repository=$(git remote -v | grep $ARGS_REMOTE_REPOS | grep push | head -1)

  cat << EOT
GITHUB_USER: $GITHUB_USER
GITHUB_REPO: $GITHUB_REPO
GITHUB_TOKEN: $GITHUB_TOKEN
build_dir: $BUILD_DEST_DIR
repository: $repository
name: $name
tag: $release
files: $UPLOAD_FILES
sha256sum.txt:
$(indent $BUILD_DEST_DIR/sha256sum.txt)
description:
$(indent "$description")
EOT
}

# validate that the deployment.yml file and other collectable data
check_name_description()
{
  local release=$1
  local name="$2"
  local description="$3"
  if [[ -z $description || $description == null || -z $name || $name == null ]] ; then
    echo "description or name not found for tag '$release' in $DEPLOYMENT_FILE"
    echo "available git tags:"
    indent "$(git tag)"
    echo "available git tags in $DEPLOYMENT_FILE:"
    indent "$(yaml_keys $DEPLOYMENT_FILE releases)"
    echo "VERSION contains"
    indent "$(cat VERSION)"
    return 1
  fi
}

main_deploy()
{
  local release=$1
  local release_version=$release

  # redefine GITHUB_TOKEN (to test if exported for bash strict mode)
  GITHUB_TOKEN=${GITHUB_TOKEN:-}

  if [[ $release == current ]] ; then
    release_version=$(cat VERSION)
    echo "using current release in VERSION: $release_version"
  fi

  local description=$(yq.v2 r $DEPLOYMENT_FILE "releases[$release_version].description")
  local name=$(yq.v2 r $DEPLOYMENT_FILE "releases[$release_version].name")
  local name=$(yq.v2 r $DEPLOYMENT_FILE "releases[$release_version].name")
  local target=$(yq.v2 r $DEPLOYMENT_FILE "target")

  # will stop the execution (as set -e is enabled)
  check_name_description $release_version "$name" "$description"

  build_binaries $release $BUILD_DEST_DIR $target
  UPLOAD_FILES=$(prepare_upload $BUILD_DEST_DIR)

  if $ARGS_n ; then
    show_release_data $release_version "$name" "$description"
    exit 0
  else
    if [[ -z $GITHUB_TOKEN ]] ; then
      error "GITHUB_TOKEN must be exported"
      return 1
    fi

    echo "deploying release $GITHUB_USER/$GITHUB_REPO: $release_version"

    if check_release $release_version ; then
      echo "release already exists: $release_version"
      if $ARGS_replace ; then
        echo "deleting existing release: $release_version"
        delete_release $release_version
        echo "creating release: $release_version"
        create_release $release_version "$name" "$description"
      else
        echo "use --replace to replace the existing release"
        echo "only uploading new files..."
      fi
    else
      echo "release doesn't exists yet: $release_version"
      echo "creating new release: $release_version"
      create_release $release_version "$name" "$description"
    fi
    if $ARGS_no_upload ; then
      echo "upload binaries skipped."
    else
      upload_binaries $release_version $UPLOAD_FILES
    fi
  fi
}

check_env()
{
  local v val
  local error=0

  for v in GOPATH GOBIN
  do
    eval "val=\${$v:-}"
    if [[ -z $val ]] ; then
      error "$v is undefined, check failed"
      error=$((error+1))
    fi
  done

  # we use docopts so i must be installed
  for v in docopts docopts.sh
  do
    if ! command -v $v > /dev/null ; then
      error "$v is not in PATH, check failed"
      error=$((error+1))
    fi
  done
  return $error
}

check_build_dir()
{
  local build_dest_dir=$1
  if [[ -d $build_dest_dir ]] ; then
    return 0
  else
    error "build_dest_dir is missing: '$build_dest_dir'"
    return 1
  fi
}

# initialize deployment for deploy.sh
# TODO: fetch dependancies? github-release docopts gox govvv go.yml
deploy_init()
{
  local files="deployment.yml get_ldflags.sh"
  local f ret
  ret=0
  for f in $files
  do
    if [[ -e $f ]] ; then
      if $ARGS_i ; then
        echo "file exists: '$f' ignored"
      else
        error "destination file exists: '$f' remove it first"
        return 1
      fi
    else
      create_template "$f"
      ret=$?
      check_file_initilized $ret "$f"
    fi
  done

  return $ret
}

check_file_initilized()
{
  local ret=$1
  local fname="$2"
  if [[ $ret -eq 0 ]] ; then
    echo "'$fname' created OK"
  else
    error "something goes wrong while creating '$fname'"
  fi
}

create_template()
{
  case $1 in
    deployment.yml)
      create_deployment_yml $1
      ;;
    get_ldflags.sh)
      create_get_ldflags $1
      ;;
    *)
      error "unknown template '$1'"
      return 1
      ;;
  esac
}

create_deployment_yml()
{
  local dest=$1
  local template="$(cat << END
---
# deploy.sh template - produced by deploy.sh init $(date "+%Y-%m-%d %H:%M:%S")
# build os/arch for gox
build:
  - darwin/386
  - darwin/amd64
  - linux/386
  - linux/amd64
  - linux/arm
  - windows/amd64

target: name_of_the_binary_to_be_built

# yaml keys must match the git tag
releases:
  v0.1:
    name: "ovh-cli for shell v0.1"
    description: |
      Your first descption.

      bla bal

      you can put some more key:
        - this thing
        - that thing too

      it doesn't have to be yaml formated thought.
END
)"

  echo "$template" > $dest
  local ret=$?
  return $ret
}

create_get_ldflags()
{
  local dest="$1"
  cat << END > "$dest"
#!/usr/bin/env bash
#
# Usage: ./get_ldflags.sh [BUILD_FLAGS]
#
# This file has been created by: deploy.sh init -- $(date "+%Y-%m-%d %H:%M:%S")
#
# This script is an helper for both Makefile + deploy.sh
#
END

  cat << 'END' >> "$dest"
# You can reuse it in your Makefile:
# BUILD_FLAGS=$(shell ./get_ldflags.sh)
# your_target: your_target.go Makefile ${OTHER_DEP}
# 	go build -o $@ -ldflags "${BUILD_FLAGS} ${LDFLAGS}"
END

  cat << 'END' >> "$dest"

set -eu
build_flags=${1:-}
if [[ -z $build_flags ]]; then
  # govvv define main.Version with the contents of ./VERSION file, if exists
  build_flags=$(govvv -flags)
fi

# you can add more flags here:
build_flags+=" -X 'main.GoBuildVersion=$(go version)' -X 'main.ByUser=${USER}'"

# the last command MUST display all build_flags
echo "$build_flags"
END
  chmod a+x "$dest"
}

# ###################################################################### main select option

if [[ $0 == $BASH_SOURCE ]] ; then
  # bash strict mode
  set -euo pipefail

  # verify the Go environment and dependancies
  check_env

  # parse command line argument with docopts
  source docopts.sh --auto -G "$@"
  if $ARGS_debug ; then
    docopt_print_ARGS -G
  fi

  # early argument action, no deep action required
  if $ARGS_init ; then
    deploy_init
    exit $?
  fi

  ######################################### argument default
  # fix docopt bug https://github.com/docopt/docopt/issues/386
  ARGS_REMOTE_REPOS=${ARGS_REMOTE_REPOS:-$ARGS_r}
  ARGS_GITHUB_USER=${ARGS_GITHUB_USER:-$ARGS_u}

  if [[ -n $ARGS_GITHUB_USER ]]; then
    GITHUB_USER=$ARGS_GITHUB_USER
  fi

  if [[ -n $ARGS_RELEASE_VERSION ]] ; then
    TAG=$ARGS_RELEASE_VERSION
  else
    echo "fetch last tag from git..."
    TAG=$(git describe --abbrev=0)
  fi

  if [[ $GITHUB_USER == 'empty' && $GITHUB_REPO == 'empty' ]] ; then
    GITHUB_REPO=""
    GITHUB_USER=""
    # try to guess it
    exports=$(git remote -v | sed -n \
    -e '/^origin.*fetch/ {
      s/\(git@github.com:\|https:..github.com.\)//
      s/origin[ 	]*//
      s/ (fetch)$//
      s/\.git$//
      s/\([^\/]*\)\/\(.*\)/export GITHUB_USER="\1";export GITHUB_REPO="\2"/
      p
    }
    ')

    echo "guessing github API info: $exports"
    eval "$exports"
  fi

  fail_if_empty GITHUB_REPO GITHUB_USER

  # ============================================================ main switch
  if $ARGS_build ; then
    check_build_dir $BUILD_DEST_DIR
    target=$(yq.v2 r $DEPLOYMENT_FILE "target")
    echo "build only ..."
    echo "dest build dir: $BUILD_DEST_DIR/"
    echo "target: '$target'"
    build_binaries $TAG $BUILD_DEST_DIR $target
    echo "============================== result:"
    ls -lh $BUILD_DEST_DIR
    exit 0
  elif $ARGS_deploy ; then
    check_build_dir $BUILD_DEST_DIR
    main_deploy $TAG
  elif $ARGS_delete ; then
    echo "deleting release $GITHUB_USER/$GITHUB_REPO: $TAG"
    delete_release $TAG
  else
    error "no command found: $*"
    exit 1
  fi
fi
