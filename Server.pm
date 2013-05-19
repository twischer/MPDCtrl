package Server;

use strict;
use warnings;
use utf8;
use Thread();
use Thread::Queue();
use IO::Socket();
use Net::hostent();
require Logger;


########################################################################################################################
sub new
########################################################################################################################
{
	my ($proto, $pobjQueue, $nPort) = @_;
	
	my $self  = {};
		
	my $class = ref($proto) || $proto;
	bless ($self, $class);
	
	if ( (not defined $nPort) or ($nPort <= 0) )
	{
		$nPort = 8061;
	}
	
	Logger->GetInstance()->Write( $self, 2, "Starting thread..." );
	$self->{'pobjThread'} = new Thread( \&WorkerThread, $self, $pobjQueue, $nPort );
	
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
	my ($self, $pobjQueue, $nPort) = @_;
	
	Logger->GetInstance()->Write( $self, 2, "Thread started" );
	
	$SIG{'TERM'} = sub { Thread->exit(); };
	
	my $pobjServer = IO::Socket::INET->new(
		'Proto'		=> "tcp",
		'LocalPort'	=> $nPort,
		'Listen'	=> $IO::Socket::INET::SOMAXCONN,
		'Reuse'		=> 1
		);
	
	Logger->GetInstance()->Write( $self, 0, "Can't setup server on port $nPort" ) unless $pobjServer;
	
	Logger->GetInstance()->Write( $self, 2, "Server is listening on port $nPort" );
	
	while ( my $pobjClient = $pobjServer->accept() )
	{
		$pobjClient->autoflush(1);
		
		my $szHostInfo = Net::hostent::gethostbyaddr( $pobjClient->peeraddr );
		Logger->GetInstance()->Write(  $self, 2, sprintf "Connect from %s", $szHostInfo ? $szHostInfo->name() : $pobjClient->peerhost()  );
		
		my $szCommand = "";
		$pobjClient->recv( $szCommand, 128 );
		
		Logger->GetInstance()->Write( $self, 2, "Command received: $szCommand" );
		
		$pobjQueue->enqueue( $szCommand );
	}
}

1;
