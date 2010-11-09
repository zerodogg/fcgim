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
use FCGIM::Constants;
use Any::Moose;
use Try::Tiny;

# Application config
has 'app' => (
	is       => 'rw',
	isa      => 'HashRef',
	required => 1,
	);
# fcgim config
has 'fullConfig' => (
    is       => 'rw',
    isa      => 'HashRef',
    required => 1,
    );

# Purpose: Start an app
sub start
{
	my $self = shift;
	die("startApp unimplemented in parent\n") if !$self->can('startApp');
	if ($self->getStatus == STATUS_RUNNING)
	{
		printv(V_NORMAL,"Already running. Maybe you wanted to restart?\n");
		return;
	}
    if (-e $self->app->{serverFile} && $self->app->{serverFile} =~ m{^/})
    {
        unlink($self->app->{serverFile});
    }
	$self->startApp();
	return 1;
}

# Purpose: Alias for ->stop to ensure naming consistency
sub stopApp
{
	my $self = shift;
	return $self->stop(@_);
}

# Purpose: Stop an app
sub stop
{
	my $self = shift;
	if ($self->getStatus == STATUS_STOPPED)
	{
		printv(V_NORMAL,$self->name.": Already stopped.\n");
	}
	elsif($self->getStatus == STATUS_DEAD)
	{
		printv(V_NORMAL,$self->name.": Already dead - removing pidfile.\n");
		unlink($self->app->{PIDFile}) or warn('Failed to unlink pidfile '.$self->app->{PIDFile}.": $!\n");
	}
	else
	{
		my $PID = $self->getPID();

		$self->msg('stopping');

		$self->killPIDloop($PID,30,true);

		if ($self->getStatus == STATUS_RUNNING)
		{
			print ' ';
			$self->msg('stillTrying');
			$self->killPIDloop($PID,30,true);
		}

		if ($self->getStatus == STATUS_RUNNING)
		{
			$self->msg('stop_error');
		}
		my $unlinkErr;
		if (-e $self->app->{PIDFile})
		{
			unlink($self->app->{PIDFile}) or $unlinkErr = $!
		}
		unlink($self->app->{serverFile});
		$self->msg('done');
		if ($unlinkErr)
		{
			printv(V_NORMAL,"The server was successfully stopped, but fcgim could not remove the PID file\n");
			printv(V_NORMAL,'at '.$self->app->{PIDFile}.": $unlinkErr\n");
			if ($< != 0 || $> != 0)
			{
				printv(V_NORMAL,"You may need to run fcgim as root.\n");
			}
			printv(V_NORMAL,"\nfcgim will consider the application \"dead\" instead of \"stopped\" until the\n");
			printv(V_NORMAL,"PID file is removed.\n");
		}
	}
	return 1;
}

# Purpose: Restart an app
sub restart
{
	my $self = shift;
	if ($self->getStatus != STATUS_RUNNING)
	{
		printv(V_NORMAL,"Application not running, just starting.\n");
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
	return 1;
}

# Purpose: Restart an app if it is dead
sub restartDead
{
    my $self = shift;
    printv(V_NORMAL,'Checking '.$self->name.'...');
	my $status = $self->getStatus();
	if ($status == STATUS_RUNNING)
	{
        printv(V_NORMAL,"running ok\n");
    }
    elsif($status == STATUS_STOPPED)
    {
        printv(V_NORMAL,"stopped\n");
    }
    else
    {
        printv(V_NORMAL,"dead - restarting\n");
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
		$outStat = 'up and running (up '.$self->uptime().'. PID '.$self->getPID().')';
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
    printv(V_NORMAL,sprintf($fmt,$self->name,$outStat));
    return 1;
}

# Purpose: Get the uptime for an app
sub uptime
{
	my $self = shift;
	if(not -e $self->app->{PIDFile} or not defined($self->getPID()))
	{
		return '(not currently up)';
	}
	my @stat = stat($self->app->{PIDFile});
	if(not @stat)
	{
		printv(V_DEBUG,'Failed to stat() '.$self->app->{PIDFILE}.': '.$!);
		return '(unknown)';
	}
	my $sUptime = time()-$stat[9];
	my $days    = int($sUptime/(24*60*60));
	my $hours   = prefixZero( ($sUptime/(60*60))%24 );
	my $mins    = prefixZero( ($sUptime/60)%60 );
	my $dayStr  = $days == 1 ? ' day,  ' : ' days, ';
	my $uptime  = $days.$dayStr.$hours.':'.$mins;
	return $uptime;
}

# Purpose: Perform a sanity check if possible
sub sanityCheck
{
	my $self = shift;
	if ($self->can('sanityCheckApp'))
	{
		$self->sanityCheckApp();
	}
	else
	{
		printv(V_NORMAL,$self->name.': is of type "'.$self->app->{type}.'" that does not support sanity checking.'."\n");
	}
    return 1;
}

# Purpose: Kill a PID
sub killPID
{
	my $self = shift;
	my $PID = shift;
	$PID = $self->getPID($PID);
    # Bail out if we have no PID
    die("killPID() failed to locate any PID to kill, bailing out\n") if not defined $PID;
	printv(V_VERBOSE,"Sending signal 15 (SIGTERM) to PID $PID\n");
	kill(15,$PID);
    return 1;
}

# Purpose: Loop trying to kill a PID N times
# Returns: true if the process is no longer running
sub killPIDloop
{
	my $self = shift;
	my $PID = shift;
	my $loop = shift;
	my $print = shift;
	$loop = ($loop =~ /\D/) ? 10 : $loop;
	$loop = ($loop > 60 || $loop < 1) ? 10 : $loop;

	$PID = $self->getPIDSafe($PID);
	return 1 if not $PID;

	foreach (0..$loop)
	{
		$self->killPID($PID);
		last if not $self->pidRunning($PID);
		sleep(1);
		print '.' if $print;
		last if not $self->pidRunning($PID);
	}
	# Our return value is the reverse of pidRunning
	return !($self->pidRunning($PID));
}

# Purpose: Kill a sanity check server
# If this suceeds, it returns true. If not, it returns false, outputs the
# 'works' ->msg(), and also outputs a message stating that it failed to kill
# the sanity check process and instructing the user to kill it manually.
sub killSanityServer
{
	my $self = shift;
	my $PID = shift;
	if(not $self->killPIDloop($PID,15,true))
	{
		$self->msg('works');
		warn("Failed to destroy the sanity check process\n");
		warn('You\'re going to need to kill PID '.$self->getPID($PID)." yourself\n");
		return false;
	}
	return true;
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
	$pid = $self->getPIDSafe($pid);
    if(not defined $pid or not length($pid))
    {
        return;
    }
	if(kill(0,$pid))
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
		if(not -e $PID)
		{
			die("PID file ($PID) does not exist\n");
		}
		open(my $i,'<',$PID) or die("Failed to read PID file $PID: $!\n");
		my $pid = <$i>;
		chomp($pid) if defined $pid;
		close($i);
		$PID = $pid;
	}
	return $PID;
}

# Purpose: Retrieve a PID, or undef if the pidfile is gone
sub getPIDSafe
{
	my $self = shift;
	my $PID = shift;
	try
	{
		$PID = $self->getPID($PID);
	}
	catch
	{
		if (/^PID file \(.+\) does not exist/)
		{
			$PID = undef;
		}
		else
		{
			die($_);
		}
	};
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
		printv(V_NORMAL,'Stopping '.$self->name.'...');
		printv(V_VERBOSE,"\n");
	}
	elsif($msg eq 'stopinsist')
	{
		printv(V_NORMAL,'failed to stop when asked nicely, forcing it to stop (sending SIGKILL)...');
		printv(V_VERBOSE,"\n");
	}
	elsif($msg eq 'starting')
	{
		printv(V_NORMAL,'Starting '.$self->name.'...');
		printv(V_VERBOSE,"\n");
	}
	elsif($msg eq 'testinstance')
	{
		printv(V_NORMAL,'Running a test instance of '.$self->name.'...');
		printv(V_VERBOSE,"\n");
	}
	elsif($msg eq 'testinstance_error' || $msg eq 'testinstance_error_restart')
	{
        printv(V_NORMAL,"failed\n");
		printv(V_NORMAL,"Test startup of new FastCGI instance failed. Something is wrong with the new\n");
		printv(V_NORMAL,'instance. ');
		if ($msg eq 'testinstance_error_restart')
		{
			printv(V_NORMAL,'The old one is still running. ');
		}
		printv(V_NORMAL,"Output from attempt to start:\n\n");
		printv(V_NORMAL,main::getCmdOutput());
		exit(1);
	}
	elsif($msg eq 'start_error')
	{
		printv(V_NORMAL,"failed\n");
		printv(V_NORMAL,"Startup of FastCGI instance failed. Output from attempt to start:\n\n");
		printv(V_NORMAL,main::getCmdOutput());
		exit(1);
	}
	elsif($msg eq 'stop_error')
	{
		printv(V_NORMAL,'failed to stop PID '.$self->getPID()."\n");
		printv(V_NORMAL,'Try killing it (kill '.$self->getPID().' or kill -9 '.$self->getPID().') yourself',"\n");
		exit(1);
	}
	elsif($msg eq 'alreadyRunning')
	{
		printv(V_NORMAL,"already running\n");
		exit(0);
	}
	elsif($msg eq 'pidDone')
	{
		printv(V_NORMAL,'done (PID '.$self->getPID().")\n");
	}
    elsif($msg eq 'works')
    {
        printv(V_NORMAL,"works\n");
    }
	elsif($msg eq 'done')
	{
		printv(V_NORMAL,"done\n");
	}
	elsif($msg eq 'stillTrying')
	{
		printv(V_NORMAL,'still trying...');
	}
    return 1;
}

# Purpose: Prepare (set perms etc.) a pid file
sub preparePIDFile
{
    my $self = shift;
    my $file = shift;
    open(my $pf,'>',$file) or die("Failed to create PID file $file: $!\n");
    close($pf);
    chown($self->app->{runAsUID},$self->app->{runAsGID},$file) or die("Failed to set permissions on PID file $file: $!\n");
    return 1;
}

# Purpose: Print a string using our verbose print helper in main::
sub printv
{
	# Allows method to work both as a function and method
	shift if(ref($_[0]));
	main::printv(@_);
}

# Purpose: Prefix a string with 0 if it is only 1 character long
sub prefixZero
{
	my $v = shift;
	if(length($v) == 1)
	{
		$v = "0$v";
	}
	return $v;
}

__PACKAGE__->meta->make_immutable;
1;
