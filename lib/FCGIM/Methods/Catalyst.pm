package FCGIM::Methods::Catalyst;
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

sub script
{
	my $self = shift;
	if ($self->fcgiScript)
	{
		return $self->fcgiScript;
	}
	my $script = glob($self->app->{path}.'/script/*_fastcgi.pl');
	if(not defined $script or not -e $script or not -x $script)
	{
		die("Failed to locate fastcgi script ($script).\n");
	}
	$self->fcgiScript($script);
	return $script;
}

sub startApp
{
	my $self = shift;
	$self->msg('starting');

	if ($self->getStatus == STATUS_RUNNING)
	{
		$self->msg('alreadyRunning');
	}

	my $r = $self->cmd($self->script,'--listen',$self->app->{serverFile},'--nproc',$self->app->{processes},'--pidfile',$self->app->{PIDFile},'--daemon');
	if ($r != 0)
	{
		$self->msg('start_error');
	}
	$self->msg('pidDone');
}

sub stopApp
{
	my $self = shift;
	my $PID = $self->getPID();

	$self->msg('stopping');
	for my $l (1..10)
	{
		if ($l < 5)
		{
			$self->msg('stopinsist') if $l == 5;
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

sub restartApp
{
	my $self = shift;
	my $tmpL = main::tempfile();
	my $tmpP = main::tempfile();
	$self->msg('testinstance');
	my $r = $self->cmd($self->script,'--listen',$tmpL,'--nproc',1,'--pidfile',$tmpP,'--daemon');
	$self->killPID($tmpP);
	unlink($tmpL); unlink($tmpP);

	if ($r != 0)
	{
		$self->msg('testinstance_error');
	}

	$self->msg('done');
	
	$self->stopApp();
	$self->startApp();
}

1;
