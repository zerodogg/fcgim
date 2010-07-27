# fcgim - FastCGI application manager
# PHP application type class
# Copyright (C) Eskild Hustvedt 2010
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# NOTE: methods in this class are never called directly from fcgim, they are
# all called by the wrappers in ::Base, which handles most of the magic.
package FCGIM::Methods::PHP;
use Any::Moose;
extends 'FCGIM::Methods::Base';

use constant {
	STATUS_RUNNING => 1,
	STATUS_STOPPED => 2,
	STATUS_DEAD    => 3,
};

has 'fcgiScript' => (
	is => 'rw',
	required => 0,
	);

# Purpose: Find a usable php5 bin
sub php5bin
{
	my $self = shift;

	foreach my $ver ('php5','php')
	{
		foreach my $form (qw(fastcgi fcgi cgi))
		{
			if(InPath($ver.'-'.$form))
			{
				return $ver.'-'.$form;
			}
		}
	}
	die("Failed to detect usable php5 fastcgi binary\n");
}

# Purpose: Start the php app
sub startApp
{
	my $self = shift;
	$self->msg('starting');

	if ($self->getStatus == STATUS_RUNNING)
	{
		$self->msg('alreadyRunning');
	}

    $self->preparePIDFile($self->app->{PIDFile});
	$ENV{PHP_FCGI_CHILDREN} = $self->app->{processes};
	my $r = $self->cmd($self->app->{PIDFile},$self->php5bin,'-b',$self->app->{serverFile});
	delete($ENV{PHP_FCGI_CHILDREN});
	if ($r != 0)
	{
		$self->msg('start_error');
	}
	$self->msg('pidDone');
	return 1;
}

# Purpose: Check for a file in path
# Usage: InPath(FILE)
sub InPath
{
	foreach (split /:/, $ENV{PATH}) { if (-x "$_/@_" and ! -d "$_/@_" ) {	return "$_/@_"; } } return 0;
}

__PACKAGE__->meta->make_immutable;
1;
