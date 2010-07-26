# fcgim - FastCGI application manager
# Base application type class
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
package FCGIM::Methods::Base;
use Any::Moose;

# Application config
has 'app' => (
	is => 'rw',
	isa => 'HashRef',
	required => 1,
	);
# fcgim config
has 'fullConfig' => (
    is => 'rw',
    isa => 'HashRef',
    required => 1,
    );

use constant {
	STATUS_RUNNING => 1,
	STATUS_STOPPED => 2,
	STATUS_DEAD    => 3,
};

# Purpose: Start an app
sub start
{
	my $self = shift;
	die("startApp unimplemented in parent\n") if !$self->can('startApp');
	if ($self->getStatus == STATUS_RUNNING)
	{
		print "Already running. Maybe you wanted to restart?\n";
		return;
	}
	$self->startApp();
}

# Purpose: Stop an app
sub stop
{
	my $self = shift;
	if ($self->getStatus == STATUS_STOPPED)
	{
		print "Already stopped.\n";
	}
	elsif($self->getStatus == STATUS_DEAD)
	{
		print "Already dead - removing pidfile.\n";
		unlink($self->app->{PIDFile});
	}
	else
	{
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
	}
}

# Purpose: Restart an app
sub restart
{
	my $self = shift;
	if ($self->getStatus != STATUS_RUNNING)
	{
		print "Application not running, just starting.\n";
		return $self->start();
	}
	elsif($self->can('restartApp'))
	{
		$self->restartApp();
	}
	else
	{
		$self->stop();
		$self->start();
	}
}

# Purpose: Restart an app if it is dead
sub restartDead
{
    my $self = shift;
    print "Checking ".$self->name."...";
	my $status = $self->getStatus();
	if ($status == STATUS_RUNNING)
	{
        print "running ok\n";
    }
    elsif($status == STATUS_STOPPED)
    {
        print "stopped\n";
    }
    else
    {
        print "dead - restarting\n";
        $self->start();
    }
    return;
}

# Purpose: Display status info for an app
sub status
{
	my $self = shift;
    my $fmt = "%-25s: %s\n";
    my $outStat;
	my $status = $self->getStatus();
	if ($status == STATUS_RUNNING)
	{
		$outStat = "up and running (PID ".$self->getPID().")";
	}
	elsif($status == STATUS_STOPPED)
	{
        $outStat = 'stopped';
	}
	elsif($status == STATUS_DEAD)
	{
        $outStat = 'DEAD!';
	}
	else
	{
        $outStat = 'UNKNOWN!';
	}
    printf($fmt,$self->name,$outStat);
}

# Purpose: Kill a PID
sub killPID
{
	my $self = shift;
	my $PID = shift;
	$PID = $self->getPID($PID);
    # Bail out if we have no PID
    die("killPID() failed to locate any PID to kill, bailing out\n") if not defined $PID;
	kill(15,$PID);
}

# Purpose: Get the status of an app
sub getStatus
{
	my $self = shift;
	if(not -e $self->app->{PIDFile} or not defined($self->getPID()))
	{
		return STATUS_STOPPED;
	}

	if ($self->pidRunning($self->app->{PIDFile}))
	{
		return STATUS_RUNNING;
	}
	return STATUS_DEAD;
}

# Purpose: Wrapper around main::cmd() and system()
# First parameter is a bool, daemonize. If you need fcgim to handle daemonizing
# the command, set it to a string - path to the pidfile to write. Otherwise set it
# to false.
sub cmd
{
	my $self = shift;
	my $daemonize = shift;
	my $gid = $);
    my $pid = $>;
	if ($gid =~ /\D/)
	{
		$gid = -1;
	}
    if(not defined $pid)
    {
        $pid = $<;
    }

    # Set environment
    my %savedENV;
    # Global environment settings from the fcgim.conf
    if(defined $self->fullConfig->{fcgim}->{ENV} && %{$self->fullConfig->{fcgim}->{ENV}} && keys(%{$self->fullConfig->{fcgim}->{ENV}}))
    {
        foreach my $k (keys(%{$self->fullConfig->{fcgim}->{ENV}}))
        {
            $savedENV{$k} = $ENV{$k};
            $ENV{$k} = $self->fullConfig->{fcgim}->{ENV}->{$k};
        }
    }
    # App-specific environment settings from this apps config
    if(defined $self->app->{ENV} && %{$self->app->{ENV}} && keys(%{$self->app->{ENV}}))
    {
        foreach my $k (keys(%{$self->app->{ENV}}))
        {
            $savedENV{$k} = $ENV{$k} if not defined $savedENV{$k};
            $ENV{$k} = $self->app->{ENV}->{$k};
        }
    }

    # Run the command, dropping priviliges if needed
    my $ret;
	if ( $self->app->{runAsUID} != $pid || $self->app->{runAsGID} != $gid )
	{
		$ret = main::cmd($self->app->{runAsGID},$self->app->{runAsUID},$daemonize,@_);
	}
    else
    {
        $ret = main::cmd(undef,undef,$daemonize,@_);
    }

    # Reset environment
    foreach my $k (keys(%savedENV))
    {
        $ENV{$k} = $savedENV{$k};
    }
    return $ret;
}

# Purpose: Check if a PID is still running
sub pidRunning
{
	my $self = shift;
	my $pid = shift;
	$pid = $self->getPID($pid);
    if(not defined $pid or not length($pid))
    {
        return;
    }
	if (-d '/proc/'.$pid)
	{
		return 1;
	}
	elsif(kill(0,$pid))
	{
		return 1;
	}
	return;
}

# Purpose: Retrieve a PID
# If supplied with an INT, assumes that is the PID
# If supplied with a string, assumes that is the path to a PID file and reads that file
# If not supplied with anything, assumes you want to read the default PID file for the current app
sub getPID
{
	my $self = shift;
	my $PID = shift;
	if(not defined $PID)
	{
		$PID = $self->app->{PIDFile};
	}
	if ($PID =~ /\D/)
	{
		open(my $i,'<',$PID) or die("Failed to read PID file $PID: $!\n");
		my $pid = <$i>;
		chomp($pid) if defined $pid;
		close($i);
		$PID = $pid;
	}
	return $PID;
}

# Purpose: Get the name of the current app
sub name
{
	my $self = shift;
	return $self->app->{name};
}

# Purpose: Output a preset message, used by subclasses
sub msg
{
	my $self = shift;
	my $msg = shift;
	if ($msg eq 'stopping')
	{
		print 'Stopping '.$self->name."...";
	}
	elsif($msg eq 'stopinsist')
	{
		print "failed to stop when asked nicely, forcing it to stop (sending SIGKILL)...";
	}
	elsif($msg eq 'starting')
	{
		print 'Starting '.$self->name."...";
	}
	elsif($msg eq 'testinstance')
	{
		print 'Running a test instance of '.$self->name.'...';
	}
	elsif($msg eq 'testinstance_error')
	{
        print "failed\n";
		print "Test startup of new FastCGI instance failed. Something is wrong with the new\n";
		print "instance. The old one is still running. Output from attempt to start:\n\n";
		print main::getCmdOutput();
		exit(1);
	}
	elsif($msg eq 'start_error')
	{
		print "failed\n";
		print "Startup of FastCGI instance failed. Output from attempt to start:\n\n";
		print main::getCmdOutput();
		exit(1);
	}
	elsif($msg eq 'stop_error')
	{
		print "failed to stop PID ".$self->getPID()."\n";
		exit(1);
	}
	elsif($msg eq 'alreadyRunning')
	{
		print "already running\n";
		exit(0);
	}
	elsif($msg eq 'pidDone')
	{
		print "done (PID ".$self->getPID().")\n";
	}
    elsif($msg eq 'works')
    {
        print "works\n";
    }
	elsif($msg eq 'done')
	{
		print "done\n";
	}
}

# Purpose: Prepare (set perms etc.) a pid file
sub preparePIDFile
{
    my $self = shift;
    my $file = shift;
    open(my $pf,'>',$file) or die("Failed to create PID file ".$file.": $!\n");
    close($pf);
    chown($self->app->{runAsUID},$self->app->{runAsGID},$file);
}

__PACKAGE__->meta->make_immutable;
1;
