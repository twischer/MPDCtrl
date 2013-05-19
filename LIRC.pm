package LIRC;
use strict;
use warnings;
use utf8;
use Thread();
use Thread::Queue();
use Lirc::Client();
use Time::HiRes();
require Logger;

########################################################################################################################
sub new
########################################################################################################################
{
	my ($proto, $pobjQueue) = @_;
	
	my $self  = {};
		
	my $class = ref($proto) || $proto;
	bless ($self, $class);
	
	Logger->GetInstance()->Write( $self, 2, "Starting thread..." );
	$self->{'pobjThread'} = new Thread( \&WorkerThread, $self, $pobjQueue );
	
	return $self;
}

########################################################################################################################
sub DESTROY
########################################################################################################################
{
	my ($self) = @_;
	
	$self->{'pobjThread'}->kill('TERM')->detach();
	Logger->GetInstance()->Write( $self, 2, "Thread exited" );
}

########################################################################################################################
sub WorkerThread
########################################################################################################################
{
	my ($self, $pobjQueue) = @_;
	
	Logger->GetInstance()->Write( $self, 2, "Thread Started" );
	my $pobjLIRC = Lirc::Client->new( {
		'prog'		=> "mpdctrl",
		'rcfile'	=> "/etc/lirc/lircrc",
		} );
	
	$SIG{'TERM'} = sub { Thread->exit(); };
	
	
	my $szCode;
	while ( $szCode = $pobjLIRC->next_code() )
	{
		Logger->GetInstance()->Write( $self, 2, "Command $szCode recived" );
		$pobjQueue->enqueue( $szCode );
	}
}

1;
