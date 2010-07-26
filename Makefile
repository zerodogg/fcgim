test:
	@for file in ./fcgim ./lib/FCGIM/Methods/Base.pm ./lib/FCGIM/Methods/Catalyst.pm; do perl -Ilib -c $$file || exit 1;done
