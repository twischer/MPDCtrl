package Logger;
use strict;
use warnings;
use utf8;
use POSIX();
use Time::HiRes();

my $m_pobjInstance;

########################################################################################################################
sub GetInstance
########################################################################################################################
{
	my ($proto) = @_;
	
	unless ($m_pobjInstance)
	{
		$m_pobjInstance  = {};
		
		my $class = ref($proto) || $proto;
		bless ($m_pobjInstance, $class);
	}
	
	return $m_pobjInstance;
}

########################################################################################################################
sub Write
########################################################################################################################
{
	my ($self, $pobjClass, $nLevel, $szMessage) = @_;
	
	my $szClassName = "";
	if (defined $pobjClass)
	{
		$szClassName = ref( $pobjClass ) . ": ";
	}
	
	my ($nSeconds, $nMicroSeconds) = Time::HiRes::gettimeofday();

	my $szTime = POSIX::strftime( "[%H:%M:%S.", localtime($nSeconds) );
	$szTime .= sprintf( "%03d]", $nMicroSeconds / 1000 );
	
	if ($nLevel == 0)
	{
		my $szText = "$szTime FATAL: $szClassName$szMessage\r\n";
		utf8::encode( $szText );
		die $szText;
	}
	elsif ($nLevel == 1)
	{
		my $szText = "$szTime WARN: $szClassName$szMessage\r\n";
		utf8::encode( $szText );
		warn $szText;
	}
	elsif ($nLevel == 2)
	{
		my $szText = "$szTime DEBUG: $szClassName$szMessage\r\n";
		utf8::encode( $szText );
		print $szText;
	}
	elsif ($nLevel == 3)
	{
		my $szText = "# $szMessage\r\n";
		utf8::encode( $szText );
		print $szText;
	}
}

1;
