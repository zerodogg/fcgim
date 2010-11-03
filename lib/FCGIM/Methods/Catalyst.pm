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
use FCGIM::Constants;

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
	my @scripts = glob($self->app->{path}.'/script/*_fastcgi.pl');
	my $script = shift(@scripts);
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
	if ($r != 0 || !$self->getPID())
	{
		$self->msg('start_error');
	}
	$self->msg('pidDone');
	return true;
}

# Purpose: Restart the catalyst app, running a test instance first
sub restartApp
{
	my $self = shift;
	if ($self->app->{sanityOnRestart})
	{
		$self->sanityCheckApp(true);
	}
	$self->stopApp();
	$self->startApp();
	return true;
}

# Purpose: Perform a sanity check
sub sanityCheckApp
{
	my $self = shift;
	my $restartMode = shift;
	my $tmpL = main::tempfile();
	my $tmpP = main::tempfile();
	$self->msg('testinstance');
    $self->preparePIDFile($tmpP);
    unlink($tmpL);
	my $r = $self->cmd(false,$self->script,'--listen',$tmpL,'--nproc',1,'--pidfile',$tmpP,'--daemon');

	# Give it another second to initialize if needed
	if (!$self->getPID($tmpP))
	{
		sleep(1);
	}

	if ($r != 0 || !$self->getPID($tmpP))
	{
		if ($self->pidRunning($tmpP))
		{
			warn("Strange, sanity check failed, but process is running.\n");
			warn('You\'re going to need to kill PID '.$self->getPID($tmpP)." yourself,\n");
		}
		if ($restartMode)
		{
			$self->msg('testinstance_error_restart');
		}
		else
		{
			$self->msg('testinstance_error');
		}
	}

	$self->killSanityServer($tmpP);
	unlink($tmpL); unlink($tmpP);

	$self->msg('works');
	return true;
}

__PACKAGE__->meta->make_immutable;
1;
