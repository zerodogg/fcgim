package FCGIM::Constants;
use strict;
use warnings;
use Exporter qw(import);

use constant {
	true                      => 1,
	false                     => 0,

	V_NORMAL                  => 1,
	V_VERBOSE                 => 2,
	V_DEBUG                   => 3,

	STATUS_RUNNING            => 1,
	STATUS_STOPPED            => 2,
	STATUS_DEAD               => 3,
	STATUS_UNKNOWN            => 4,
	STATUS_UNKNOWN_PERMDENIED => 5
	};
our @EXPORT = qw(true false V_NORMAL V_VERBOSE V_DEBUG STATUS_RUNNING STATUS_STOPPED STATUS_DEAD STATUS_UNKNOWN STATUS_UNKNOWN_PERMDENIED);
