#
# Makefile for deploy.sh
#

#PREFIX ?= /usr/local
PREFIX ?= ${HOME}/.local

DOCOPTS=${PREFIX}/bin/docopts

# dependancies
install_builddep:
	go get github.com/docopt/docopts
	go get github.com/mitchellh/gox
	go get github.com/github-release/github-release
	go get gopkg.in/yaml.v2
	go get github.com/ahmetb/govvv

###########################

# requires write access to $PREFIX
install:
	install -m 755 deploy.sh $(PREFIX)/bin/deploy.sh
