prefix ?= /usr/local/
BINDIR ?= $(prefix)bin
DATADIR ?= $(prefix)share
VERSION=$(shell ./fcgim --version|perl -pi -e 's/^\D+//; chomp')
DISTFILES=fcgim Makefile fcgim.conf README COPYING lib fcgim.1

default: test

test:
	@for file in ./fcgim ./lib/FCGIM/Methods/Base.pm ./lib/FCGIM/Methods/Catalyst.pm ./lib/FCGIM/Methods/PHP.pm; do perl -Ilib -c $$file || exit 1;done
clean:
	rm -f `find|egrep '~$$'`
	rm -rf fcgim-$(VERSION)
	rm -f fcgim-*.tar.bz2 fcgim.1
install: test
	mkdir -p "$(DATADIR)/fcgim"
	cp -r fcgim lib "$(DATADIR)/fcgim"
	ln -sf "$(DATADIR)/fcgim/fcgim" "$(BINDIR)"
	[ -e "/etc/fcgim.conf" ] || cp fcgim.conf /etc/
	[ -e fcgim.1 ] && mkdir -p "$(DATADIR)/man/man1" && cp fcgim.1 "$(DATADIR)/man/man1" || true
uninstall:
	rm -rf "$(DATADIR)/fcgim"
	rm -f "$(BINDIR)/fcgim" "$(DATADIR)/man/man1/fcgim.1"
man:
	pod2man --name "fcgim" --center "" --release "fcgim $(VERSION)" ./fcgim ./fcgim.1
distrib: clean test man
	mkdir -p fcgim-$(VERSION)
	cp -r $(DISTFILES) ./fcgim-$(VERSION)
	tar -jcvf fcgim-$(VERSION).tar.bz2 ./fcgim-$(VERSION)
	rm -rf fcgim-$(VERSION)
	rm -f fcgim.1
