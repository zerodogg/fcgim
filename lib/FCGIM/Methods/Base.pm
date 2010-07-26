package FCGIM::Methods::Base;
use Any::Moose;

has 'app' => (
	is => 'rw',
	isa => 'HashRef',
	required => 1,
	);
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

sub stop
{
	my $self = shift;
	die("stopApp unimplemented in parent\n") if !$self->can('stopApp');
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
		return $self->stopApp();
	}
}

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

sub killPID
{
	my $self = shift;
	my $PID = shift;
	$PID = $self->getPID($PID);
    die("killPID() failed to locate any PID to kill, bailing out\n") if not defined $PID;
	kill(15,$PID);
}

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

sub cmd
{
	my $self = shift;
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
    if(defined $self->fullConfig->{fcgim}->{ENV} && %{$self->fullConfig->{fcgim}->{ENV}} && keys(%{$self->fullConfig->{fcgim}->{ENV}}))
    {
        foreach my $k (keys(%{$self->fullConfig->{fcgim}->{ENV}}))
        {
            $savedENV{$k} = $ENV{$k};
            $ENV{$k} = $self->fullConfig->{fcgim}->{ENV}->{$k};
        }
    }
    if(defined $self->app->{ENV} && %{$self->app->{ENV}} && keys(%{$self->app->{ENV}}))
    {
        foreach my $k (keys(%{$self->app->{ENV}}))
        {
            $savedENV{$k} = $ENV{$k} if not defined $savedENV{$k};
            $ENV{$k} = $self->app->{ENV}->{$k};
        }
    }

    my $ret;
	if ( $self->app->{runAsUID} != $pid || $self->app->{runAsGID} != $gid )
	{
		$ret = main::cmd($self->app->{runAsGID},$self->app->{runAsUID},@_);
	}
    else
    {
        $ret = main::cmd(undef,undef,@_);
    }

    foreach my $k (keys(%savedENV))
    {
        $ENV{$k} = $savedENV{$k};
    }
    return $ret;
}

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

sub name
{
	my $self = shift;
	return $self->app->{name};
}

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

sub preparePIDFile
{
    my $self = shift;
    my $file = shift;
    open(my $pf,'>',$file) or die("Failed to create PID file ".$file.": $!\n");
    close($pf);
    chown($self->app->{runAsUID},$self->app->{runAsGID},$file);
}

1;
