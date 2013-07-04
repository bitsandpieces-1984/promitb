#!/usr/bin/perl -w

###############################################################################
# pragmas
###############################################################################
use strict ;
use warnings ;

###############################################################################
# cpan modules
###############################################################################
use WWW::Mechanize ;			# for the http authentication, post/get/put
use MIME::Base64 ;				# need to encode the username/password provided to add to http header
use XML::Simple ;				# else how will i read the config file
use Getopt::Long;				# cli argument processing
use JSON ;						# webservices, means json so for json to xml and vice versa
use Data::Dumper ;				# do i need to explain this ;)
use Log::Log4perl qw(:easy) ;	# logging module

###############################################################################
# script input processing/usage info 
###############################################################################
&usage() unless ( @ARGV ) ;

#
# read the cli inputs
#
my ( $repo, $cmd, $args, $help, $debug, $config_file ) ;
$config_file = 'request_config.xml';
eval {
	
	GetOptions(
		"repo=s"		=> \$repo ,
		"cmd=s"			=> \$cmd ,
		"args=s"		=> \$args ,
		"help"			=> \$help ,
		"debug=i"		=> \$debug ,
		"config=s"		=> \$config_file ,
	) or &usage();

} ;  

die "Could not display usage info:$@" if ( $@ );

#
# display usage if requested so
#
&usage() if ( $help ) ;
my @args = split ( /\s+/, $args ) if ( defined $args );

###############################################################################
# logging section
###############################################################################
my $logfile = &_date_time( 1 ) . ".log" ;
my $logger = &_initLog( "logs/$logfile", $debug );

$logger->info ("+"x80 );
$logger->info ("+",  sprintf "%50s", "Start of ".&_date_time."-$$.log" );
$logger->info ("+"x80 );

my $cli = qx/ps -o args $$/ ;
$cli =~ s/\s+/ /g;

$logger->info ( 
	sprintf "%15s $cli", 
	'CLI:' 
);

###############################################################################
# config data
###############################################################################
my $action_map 	= &_readconfig ( 'actionmap.xml' )->{'action_maps'} ;
$action_map 	= &_verifyactionmap ( $action_map ) ;

my $config 		= &_readconfig ( $config_file ) ;
#$config 	= &_verifyuserconfig ( $config ) ;

###############################################################################
# main method calls
###############################################################################
&_validate_args ( $cmd, $repo, \@args, $action_map )  ;
&make_request ( $cmd, '', \@args, $action_map ) ;

END {
	
	if ( defined $logger ) { 
	
		$logger->info ("+"x80 );
		$logger->info ("+",  sprintf "%50s", "End of ".&_date_time."-$$.log" );
		$logger->info ("+"x80 );
	
	}		
	
}

###############################################################################
# sub routine defination from here on
###############################################################################

=pod

=over 4

=item usage();
	provides the usage and basic validate that user submits the
	expected args

Usage:
	&usage( @ARGV);

Return:
	exits the script with needed messsage if arguments are not correct
	simply returns if everything works as expected

=back

=cut

############################################################
sub usage () {
############################################################
	
	my $action_map	= shift ;
	my $cmd 		= shift || undef ;

	#
	# if action map is not read and verify it 
	#
	unless ( defined $action_map ) {
	
		$action_map 	= &_readconfig ( 'actionmap.xml' )->{'action_maps'} ;
		$action_map 	= &_verifyactionmap ( $action_map );
		
	}
	
	#
	# if command is passed, show usage only for command
	#
	my $usage = "Usage: \t$0 --help\n" ;
	if ( defined $cmd ) { 
		
		$usage =   sprintf  "\t$0 --cmd %-8s  --args '%s' [--repo reponame]\n" , $cmd , "@{$action_map->{$cmd}->{'required'}}" ;
	
	} else {
	
		map{
			$usage .=   sprintf  "\t$0 --cmd %-8s --args %-29s [--repo reponame]\n" , $_, "'@{$action_map->{$_}->{'required'}}'" ;
		} sort keys %{$action_map} ;
	
	}
	
	$usage.= "\t--repo if not specified will be picked up from config file\n";
	print $usage ;
	exit -1 ;
	
############################################################
}; # end subrotuine usage
############################################################


=pod

=over 4

=item initLog();

Method Description:
	instansiates the static object of Log4perl
Usage:
	initLog ( $logdir, $debug )

Returns:
	logger object

=back

=cut

#################################################################
sub _initLog() {
#################################################################

    my ( $log_file, $debug ) = @_;

    my $debug_mode = 'INFO';

    $debug_mode = 'DEBUG' if ( defined $debug );
    $debug_mode = 'TRACE' if ( defined $debug && $debug > 1 );

    print STDERR "$debug_mode File Details: $log_file\n";

    # Define Configuration in a string ...
    my $log_conf = qq(
		log4perl.logger=$debug_mode, LOGFILE

		log4perl.appender.LOGFILE=Log::Log4perl::Appender::File
		log4perl.appender.LOGFILE.filename=__LOGFILE_NAME__
		log4perl.appender.LOGFILE.mode=append

		log4perl.appender.LOGFILE.layout=Log::Log4perl::Layout::PatternLayout
		log4perl.appender.LOGFILE.layout.ConversionPattern=[%d] %L - %m%n
	);
    $log_conf =~ s/__LOGFILE_NAME__/$log_file/gs if ($log_file);
    Log::Log4perl->init( \$log_conf );
    my $logger = get_logger('request.pl');
    return $logger;

#################################################################
}
#################################################################

=pod

=over 4

=item _date_time();
	Utility method to return the current data time seperated by _
	Meant to be used to create the logfile name

Usage would be
	my $date_time = _date_time()

=back

=cut

################################################################
sub _date_time () {
################################################################

	my $flag = shift || '';
	
    my @localtime = localtime(time);
    my $date_time = join( "",
        $localtime[5] + 1900,
        sprintf( "_%02d", ( $localtime[4] + 1 ) ),
        sprintf( "_%02d", $localtime[3] ),
        sprintf( "_%02d", $localtime[2] ),
        sprintf( "_%02d", $localtime[1] ),
    );

	$date_time =~ s/_\d{2}_\d{2}$// if ( $flag ) ;
    return $date_time;

################################################################
}
################################################################

=pod

=over 4

=item _readconfig();
	reads a xml based config file using XML::Simple

Usage:
	&_readconfig ( $filename );

Return:

=back

=cut

############################################################
sub _readconfig () {
############################################################

	my $file = shift ;
	
	die "File $file does not exists:$!" unless ( -e $file ) ;
	die "File $file does not exists:$!" unless ( -r $file ) ;
	return XMLin ( $file ) or  die ( "Could not open file $file for user config:$!"  ) ;

############################################################
}
############################################################

=pod

=over 4

=item _verifyactionmap ();
	

Usage:
	&_readconfig ( $filename );

Return:

=back

=cut

############################################################
sub _verifyactionmap () {
############################################################

	my $actionmap = shift ;
	
	map{
		$actionmap->{$_}->{'required'} =  [$actionmap->{$_}->{'required'}] unless ( ref ( $actionmap->{$_}->{'required'} ) =~ /ARRAY/ ); 
	} keys %{$actionmap} ;
	
	return $actionmap ;
	
############################################################
}
############################################################


=pod

=over 4

=item validate_args();
	basic validate that user args

Usage:
	&validate_args ( @ARGV);

Return:

=back

=cut

############################################################
sub _validate_args () {
############################################################
	
	my ( $cmd, $repo, $args, $action_map ) = @_ ;
	$logger = get_logger('validate_args');
	
	#
	#
	#
	unless ( exists $action_map->{$cmd} ) {
		$logger->error ( "Command $cmd not supported" );
		&usage( $action_map );
	}

	#
	# pick up repo config if not specified in cli
	#
	$repo = $repo || $config->{'LoginDetails'}->{'DefaultRepo'} ;
	unless ( defined $repo ) {
		$logger->error ( "Repositary name needs to be specified" );
		&usage( $action_map, $cmd );
	}	

	unless ( defined $args ) {
		$logger->error ( "arguments need to be provided for command" );
		&usage( $action_map, $cmd );
	}	
	
	my $expected_args = $action_map->{$cmd}->{'required'} ;
	unless ( scalar @{$args} == scalar @{$expected_args}  ) {
		$logger->error ( "Expected ", scalar @{$expected_args}, " argument(s) @{$expected_args} for command $cmd" );
		&usage( $action_map, $cmd );
	}

	$logger->debug ( sprintf "%15s $cmd",	"Command:" );
	$logger->debug ( sprintf "%15s @args",	"Args:" );
	$logger->debug ( sprintf "%15s $repo",	"Repo:" );
	
	unshift ( @args , $repo );	

############################################################
}; # end subrotuine validate_args
############################################################

=pod

=over 4

=item process_main();
	construct the url and calls the _request method
Usage:
	&process_main ( $cmd, $repo, $args, $action_map );

Return:

=back

=cut

############################################################
sub make_request () {
############################################################

	my ( $cmd, $repo, $args, $action_map ) = @_ ;
	
	#
	# construct the param for _request 
	#
	my $param = {
		'CMD'	=> 	$cmd ,
		'OPERATION'	=>	$action_map->{$cmd}->{'request_type'}  ,
		'URI'		=>	$action_map->{$cmd}->{'uri'} ,
		'USERNAME'	=>	$config->{'LoginDetails'}->{'UserName'} ,
		'PASSWORD'	=>	$config->{'LoginDetails'}->{'PassWord'} ,
		'BASE_URL'	=>	$config->{'LoginDetails'}->{'HostUrl'} ,
	};
	 
	$logger->debug ( 
		sprintf "%15s $action_map->{$cmd}->{'uri'}",	
		"RELATIVE URI:" 
	) if ( defined $action_map->{$cmd}->{'uri'} );
	
	$logger->debug ( 
		sprintf "%15s $config->{'LoginDetails'}->{'UserName'}",	
		"USERNAME:" 
	);
	
	$logger->debug ( 
		sprintf "%15s $config->{'LoginDetails'}->{'PassWord'}",	
		"PASSWORD:" 
	);
	
	$logger->debug ( 
		sprintf "%15s $config->{'LoginDetails'}->{'HostUrl'}",	
		"BASE URL:" 
	);
	
	if ( $cmd =~ /checkout/ ) {
		
		my $file_name = pop @{$args} ;

		die "$file_name is not a directory" unless ( -d $file_name ) ;		
		$file_name = './' if ( $file_name =~ /^\.$/ );
		$file_name =~ s/$/\// unless $file_name =~ /\/$/;
		
		my $remote_file = $args[$#args] ;
		$remote_file =~ s/.*\/(.*?)/$1/ if ( $remote_file =~ /\// );
		
		$param->{'LOCAL_FILENAME'} = $file_name.$remote_file ;
			
	} elsif ( $cmd =~ /checkin/ ) {
		
		my $file_name = pop @{$args} ;		
		my $upload_name = $file_name ;
		
		$upload_name =~ s/.*\/(.*?)/$1/ if ( $upload_name =~ /\// );
		$args[$#args] = $args[$#args].'/'.$upload_name ;

		$logger->debug ( 
			"%10s $file_name", 'Checkin Loc' 
		) ;
		&error ( "-ERROR-\tLocal file doesnt exists :$file_name", 1 ) unless ( -e $file_name ) ;

		open ( FH , $file_name ) or error ( "-ERROR-\tCould not read file: $file_name:$!", 1 );
		binmode ( FH ) if ( $file_name =~ /\.(jar|zip)$/ );
		undef $/ ; 
		$param->{'FILE_DATA'} = <FH>;	
	
	} elsif ( $cmd =~ /((?:mkdir)|(?:rmdir))/  ) {
		$args[$#args] .= '/'; 
	} else {
		# do nothing extra 	
	}
	
	&_request (
		{
			%{$param} ,
			'ARGS'		=>	join ( '/' ,  @args  ) ,
		}
	);
	
############################################################
} # end of process_main
############################################################


=pod

=over 4

=item process_main();
	construct the url and calls the _request method
Usage:
	&process_main ( $cmd, $repo, $args, $action_map );

Return:

=back

=cut

############################################################
sub _request () {
############################################################

	my $args = shift ;		
	my $client = WWW::Mechanize->new();

	#
	# add the authentication part
	#
	$client->add_header (
		'Authorization' ,
		'Basic ' . encode_base64 (
			$args->{'USERNAME'} . ':' . $args->{'PASSWORD'}
		)
	);
	
	#
	# url construction
	#
	$args->{'URL'} = $args->{'BASE_URL'} .	'/' . '__URI__'. $args->{'ARGS'} ;
	my $uri = '';	

	$uri = $args->{'URI'} . '/'  if ( defined $args->{'URI'} );
	$args->{'URL'} =~ s/__URI__/$uri/;
	
	$logger->debug ( 
		sprintf "%15s $args->{'URL'}", 
		'REQUEST URL:' 
	) ;
	$logger->debug ( 
		sprintf "%15s %s", 
		'OPERATION:', 
		uc $args->{'OPERATION'}  
	) ;
	
	#
	# actual method call
	#
	eval {
			
		my $operation = $args->{'OPERATION'} ;
		if ( exists $args->{'FILE_DATA'} ) {
			$client->$operation (
				$args->{'URL'},
				'Content' => $args->{'FILE_DATA'} ,
			);
		} else {
			$client->$operation (
				$args->{'URL'},
			);	
		}
	
	};
		
	&error ( "-ERROR-\t\t$@\n", 1 ) if ( $@ ) ;

	#
	# parsing the response
	#
	my $response 	= $client->response() ;
	my $status 		= 	"RESTapi Call __STATUS__" . "\n" ;
	my $status_code	= 	$response->status_line() ;

	if ( $response->is_success ) {

		$status =~  s/__STATUS__/Success/ ;		
		eval {
			if ( $args->{'CMD'} =~ /checkout/ ) {
				$logger->debug ( "-DEBUG-\t\tLocation:$args->{'LOCAL_FILENAME'}" );
				$client->save_content( $args->{'LOCAL_FILENAME'} )  ;
			
			}	 	
		} ;
		
		if ( $@ ) { 
		
			$status =~ s/__STATUS__/Failed/ ; 
			error ( "-ERROR-\t\tCould not write file to local file:$args->{'LOCAL_FILENAME'}", 1 ) 
	
		}
	
	} else {
	
		$status =~  s/__STATUS__/Failed/ ;			
		error ( "-ERROR-\t\t$status", 1 ) 
	
	}
	
	&_dumpresponse ( $response->decoded_content(), $status, $status_code ) ;

	
###############################################################################
} # end of &_request()
###############################################################################

###############################################################################
sub _dumpresponse () {
###############################################################################
	
	my $data = shift ;
	my $status = shift ;
	my $status_code  = shift ;
	
	$logger->debug ( 
		sprintf "%15s $status", 
		'STATUS:'
	);

	$logger->debug ( 
		sprintf "%15s $status_code", 
		'STATUS CODE:'
	);


	eval {
		#$logger->debug ( Dumper from_json ( $data ) );
	};

}

sub error () {
	
	my $error = shift ;
	my $die	  = shift ;
	$logger->error ( "-ERROR-\t$error") ;
	die "$error" if ( $die );
	
}

