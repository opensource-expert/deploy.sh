# build and release code to github

`deploy.sh` is a shell wrapper based on Go binaries to automate deployment of new release to github, using the github
API.

It is originaly build to push pre-built binaries of my golang opensource project to github releases.

This tool is for developper, you will need a Go workspace.

## Status: Draft

The scripts is working on my environment

## Usage

We provide a deploy script, which will take the last git tag, and a deployment
message written in a yaml file `deployment.yml`.

So you need to create the release text in `deployment.yml` before you run
`deploy.sh`.

See what will going on (dry-run):

```
./deploy.sh deploy -n
```

Deploy and replace existing binaries for this release.

```
./deploy.sh deploy --replace
```

Only build binaries in `build/` dir:

```
./deploy.sh build
```

## Requirements

In order to release binaries you will need some granted access to github API.

You will also need some more developper tools.

Most of the tools require a working [Go developper
environment](https://golang.org/doc/code.html#Organization). Which should not be too
complicated to setup.

All dependancies are installed in your Go workspace with:

```
make install_builddep
```

Go for the details:

### docopts

A shell command-line parser for making beautiful CLI with ease

```
go get github.com/docopt/docopts
```

### gox

Cross-compiled binaries are built with [gox](https://github.com/mitchellh/gox)

```
go get github.com/mitchellh/gox
```

### govvv

Version are embedded at compile time in Go with [govvv](https://github.com/ahmetb/govvv)

```
go get github.com/ahmetb/govvv
```

### github release uploader

Releases are published to github releases using github API with [gothub](https://github.com/itchio/gothub)

```
go get github.com/itchio/gothub
```

### github API token

You will need a valid gitub token for the target repository.

https://help.github.com/articles/creating-an-access-token-for-command-line-use

The token needs to have `repos` auth priviledges.

Export your `GITHUB_TOKEN` as a bash environment variable:

```
export GITHUB_TOKEN="your token here"
```

### git tag a new release

We use [semantic verion tags](https://semver.org/)

The current version is stored in the file `VERSION` which will be used by `govvv`.

```
echo "v0.6.3-alpha2" > VERSION
git tag -a "$(cat VERSION)" -m "golang 2019"
git push origin "$(cat VERSION)"
```

### yaml command-line tool

**Experimental**

See: http://mikefarah.github.io/yq/

For extracting yaml data from `deployment.yml`

```
go get gopkg.in/mikefarah/yq.v2
```

### build golang project binaries

Our script uses `docopts` for parsing our command line option.

```
make
```

