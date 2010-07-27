# fcgim - FastCGI application manager
# Catalyst application type class
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
package FCGIM::Methods::Catalyst;
use Any::Moose;
extends 'FCGIM::Methods::Base';

use constant {
	STATUS_RUNNING => 1,
	STATUS_STOPPED => 2,
	STATUS_DEAD    => 3,
	true => 1,
	false => 0,
};

has 'fcgiScript' => (
	is => 'rw',
	required => 0,
	);

# Purpose: Retrieve the path to the catalyst app script
sub script
{
	my $self = shift;
	if ($self->fcgiScript)
	{
		return $self->fcgiScript;
	}
	if(not -d $self->app->{path}.'/script/')
	{
		die($self->app->{path}.'/script/: does not exist. Failed to locate fastcgi script.'."\n");
	}
	my $script = glob($self->app->{path}.'/script/*_fastcgi.pl');
	if(not defined $script or not -e $script or not -x $script)
	{
		if (defined $script)
		{
			die("Failed to locate fastcgi script ($script).\n");
		}
		else
		{
			die("Failed to locate fastcgi script.\n");
		}
	}
	$self->fcgiScript($script);
	return $script;
}

# Purpose: Start the catalyst app
sub startApp
{
	my $self = shift;
	$self->msg('starting');

	if ($self->getStatus == STATUS_RUNNING)
	{
		$self->msg('alreadyRunning');
	}

    $self->preparePIDFile($self->app->{PIDFile});
	my $r = $self->cmd(false,$self->script,'--listen',$self->app->{serverFile},'--nproc',$self->app->{processes},'--pidfile',$self->app->{PIDFile},'--daemon');
	if ($r != 0)
	{
		$self->msg('start_error');
	}
	$self->msg('pidDone');
}

# Purpose: Stop the catalyst app
sub stopApp
{
	my $self = shift;
	my $PID = $self->getPID();

	$self->msg('stopping');
	for my $l (1..10)
	{
		if ($l > 5)
		{
			$self->msg('stopinsist') if $l == 6;
			kill(9,$PID);
		}
		else
		{
			kill(15,$PID);
		}

		last if $self->getStatus != STATUS_RUNNING;
		sleep(1);
		last if $self->getStatus != STATUS_RUNNING;
	}

	if ($self->getStatus == STATUS_RUNNING)
	{
		$self->msg('stop_error');
	}
	unlink($self->app->{PIDFile});
	unlink($self->app->{serverFile});
	$self->msg('done');
	return 1;
}

# Purpose: Restart the catalyst app, running a test instance first
sub restartApp
{
	my $self = shift;
	my $tmpL = main::tempfile();
	my $tmpP = main::tempfile();
	$self->msg('testinstance');
    $self->preparePIDFile($tmpP);
    unlink($tmpL);
	my $r = $self->cmd(false,$self->script,'--listen',$tmpL,'--nproc',1,'--pidfile',$tmpP,'--daemon');

	if ($r != 0 || !$self->getPID($tmpP))
	{
		$self->msg('testinstance_error');
	}

	$self->killPID($tmpP);
	unlink($tmpL); unlink($tmpP);

	$self->msg('works');
	
	$self->stopApp();
	$self->startApp();
}

__PACKAGE__->meta->make_immutable;
1;
