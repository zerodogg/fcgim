prefix ?= /usr/local/
BINDIR ?= $(prefix)bin
DATADIR ?= $(prefix)share

default: test

test:
	@for file in ./fcgim ./lib/FCGIM/Methods/Base.pm ./lib/FCGIM/Methods/Catalyst.pm; do perl -Ilib -c $$file || exit 1;done
clean:
	rm -f `find|egrep '~$$'`
install: test
	mkdir -p "$(DATADIR)/fcgim"
	cp -r fcgim lib "$(DATADIR)/fcgim"
	ln -sf "$(DATADIR)/fcgim/fcgim" "$(BINDIR)"
	[ -e "/etc/fcgim.conf" ] || cp fcgim.conf /etc/
uninstall:
	rm -rf "$(DATADIR)/fcgim"
	rm -f "$(BINDIR)/fcgim"
