#
# Makefile for deploy.sh
#

#PREFIX ?= /usr/local
PREFIX ?= ${HOME}/.local

# dependancies
GOVVV=${GOPATH}/bin/govvv
DOCOPTS=${PREFIX}/bin/docopts

install_builddep: ${GOVVV}
	go get github.com/mitchellh/gox
	go get github.com/itchio/gothub
	go get gopkg.in/mikefarah/yq.v2
	go get github.com/docopt/docopts

${GOVVV}:
	go get github.com/ahmetb/govvv

###########################

# requires write access to $PREFIX
install:
	install -m 755 deploy.sh $(PREFIX)/bin/deploy.sh
