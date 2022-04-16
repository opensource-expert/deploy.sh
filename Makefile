#
# Makefile for deploy.sh
#

#PREFIX ?= /usr/local
PREFIX ?= ${HOME}/.local

DOCOPTS=${PREFIX}/bin/docopts

# dependancies
install_builddep:
	go install github.com/docopt/docopts
	go install github.com/mitchellh/gox
	go install github.com/github-release/github-release
	go install github.com/mikefarah/yq/v4@latest
	go install github.com/ahmetb/govvv

###########################

# requires write access to $PREFIX
install:
	install -m 755 deploy.sh $(PREFIX)/bin/deploy.sh
