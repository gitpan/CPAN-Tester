package CPAN::Tester;

$VERSION = '0.01_10';
@EXPORT_OK = qw(new poll test);

use strict;
use warnings;
no warnings qw(redefine);
use Carp 'croak';
use ExtUtils::MakeMaker;
use File::Slurp;
use Net::FTP;
use Test::Reporter;

our $VERSION = '0.01_10';
our $NAME = 'CPAN::Tester';

$| = 1;

sub new {
    my ($self, $conf, $opt) = @_;  
    my $class = ref( $self ) || $self;
    
    my %blessed; 
    %{$blessed{CONF}} = %{$conf};
    %{$blessed{OPT}}  = %{$opt};      
     
    return bless( \%blessed, $class );
}

sub test {
    no strict 'refs';
    my ($self) = @_;
    
    open( my $track, ">>$self->{CONF}{trackfile}" ) or $self->_report_mail( "Couldn't open $self->{CONF}{trackfile} for writing: $!\n " );
    
    $self->fetch;
    $self->read_track;
    
    $self->{ftp} = $self->_ftp_initiate;
    
    while (@{$self->{files}}) {
        if ($self->{got_file}->{${$self->{files}}[0]} || ${$self->{files}}[0] !~ /tar.gz$/) {
            shift @{$self->{files}};
	    next;
	}
	
	($self->{dist}) = ${$self->{files}}[0] =~ /(.*)\.tar.gz$/;
	
	unless ($self->_test) {
	    $self->{got_file}{${$self->{files}}[0]} = 1;
	    print $track "${$self->{files}}[0]\n";
	    shift @{$self->{files}};
	}
    }
    close( $track ) or $self->_report_mail( "Couldn't close $self->{CONF}{trackfile}: $!\n" );

    $self->{ftp}->quit;
}

sub poll {
    my ($self) = @_;
    
    while (1) { 
        my $string = 'second(s) until poll';
	my $oldlen = 0;
	    
	$self->test;
	    
	for (my $sec = $self->{OPT}{poll}; $sec >= 1; $sec--) {
	    $self->do_verbose( \*STDERR, "$self->{CONF}{prefix} $sec " );
		
            my $fulllen = (length( $self->{CONF}{prefix} ) + 1 + length ( $sec ) + 1 + length( $string ));
	    $oldlen = $fulllen unless $oldlen;
	    my $blank = $oldlen - $fulllen;
	    $oldlen = $fulllen;
		
	    print( $string, ' ' x $blank, "\b" x ($fulllen + $blank) ) if ($self->{OPT}{verbose} && $sec != 1);
	    $blank = 0;
		
	    sleep 1;
	}
        $self->do_verbose( \*STDERR, "\n--> Polling\n" );
    }
}

sub fetch {
    my ($self) = @_;
    my @files;
    
    $self->{ftp} = $self->_ftp_initiate;
      
    if ($self->{CONF}{rss}) {    
	require LWP::UserAgent;
 
        my $ua = LWP::UserAgent->new;
        my $response = $ua->get( $self->{CONF}{rss_feed} );
 
        if ($response->is_success) {
            @files = $response->content =~ /<title>(.*?)<\/title>/gm;  
        } else {
            $self->_report_mail( $response->status_line );
        }
	
	$self->{ftp}->cwd( $self->{CONF}{rdir} )
          or $self->_report_mail( "Couldn't change working directory: ", $self->{ftp}->message ); 
    } else {
        $self->{ftp}->cwd( $self->{CONF}{rdir} )
          or $self->_report_mail( "Couldn't change working directory: ", $self->{ftp}->message );
        
	@files = $self->{ftp}->ls()
          or $self->_report_mail( "Couldn't get list from $self->{CONF}{rdir}: ", $self->{ftp}->message );
    }
   
    @{$self->{files}} = sort @files[ 2 .. $#files ];
}

sub read_track {
    my ($self) = @_;   

    my $track = read_file( $self->{CONF}{trackfile} ) or die "Could not read $self->{CONF}{trackfile}: $!\n";
    %{$self->{got_file}} = map { $_ => 1 } split /\n/, $track;
}

sub weed_out_track {
    my ($self) = @_;
    my %file;
    
    local $" = "\n";
    
    my $trackf = read_file( $self->{CONF}{trackfile} ) or die "Could not open $self->{CONF}{trackfile} for reading: $!\n";
    my @track = split /\n/, $trackf;

    for (my $i = 0; $i < @track; ) {
        if ($file{$track[$i]}) {
	    splice (@track, $i, 1);
	    next;
	}
        $file{$track[$i]} = 1;
	$i++;
    }
    
    @{$self->{track}} = sort @track;
    
    open( my $track, ">$self->{CONF}{trackfile}" ) or die "Could not open $self->{CONF}{trackfile} for writing: $!\n";
    print $track "@{$self->{track}}\n";
    close( $track ) or die "Could not close $self->{CONF}{trackfile}: $!\n";
}

sub do_verbose {
    no strict 'refs';
    my ($self, $out, @err) = @_;
    
    $out->print( @err ) if ($self->{OPT}{verbose});
}

sub _test {
    my ($self) = @_;
    
    return 0 unless $self->_process( '', "$self->{dist} - Process? [Y/n]: " );
	
    unless ($self->_is_prereq) {
        $self->{ftp}->cwd( $self->{CONF}{rdir} )
          or $self->_report_mail( "Couldn't change working directory: ", $self->{ftp}->message );
        $self->{ftp}->get( $self->{files}->[0], "$self->{CONF}{dir}/${$self->{files}}[0]" )
          or $self->_report_mail( "Couldn't get ${$self->{files}}[0]: ", $self->{ftp}->message );
    }
	
    chdir( $self->{CONF}{dir} ) or $self->_report_mail( "Couldn't cd to $self->{CONF}{dir}: $!\n" );
	
    return 0 unless $self->_process( "tar xvvzf ${$self->{files}}[0] -C $self->{CONF}{dir}" );
    $self->_report_mail( "$self->{dist}: tar xvvzf ${$self->{files}}[0] -C $self->{CONF}{dir}: $?\n" ) if $?;
	
    $self->{dist_dir} = "$self->{CONF}{dir}/$self->{dist}";
	
    return 0 if $self->_cd_error;

    return 0 unless $self->_process( 'perl Makefile.PL' );
	
    local *ExtUtils::MakeMaker::WriteMakefile = \&_get_prereqs;
    $self->{makeargs} = $self->_run_makefile;
	
    my $install_prereqs = 0;
	
    if ($self->_process_prereqs) {
        unshift( @{$self->{files}}, @{$self->{prereqs}} );
        %{$self->{install_prereqs}} = map { $_ => 1 } @{$self->{prereqs}};
        return 0;
    }

    return 0 unless $self->_process( 'make' );
    return 0 unless $self->_process( 'make install' );
    return 0 unless $self->_process( 'make test' );
    unless ($self->_is_prereq) {
        return 0 unless $self->_process( '', 'report? [Y/n]: ' ); 
        $self->_report( $self->{dist} );
    }
    return 0 unless $self->_process( 'make realclean' ); 
    return 0 unless $self->_process( "rm -rf $self->{dist}_dir" );
    
    return 0;
}

sub _fetch_prereq {
    my ($self) = @_;    
    my ($distcmp, $distdir, @distindex_);
    
    my $moduleindex = 'http://www.cpan.org/modules/01modules.index.html';
    
    $self->do_verbose( \*STDERR, "$self->{CONF}{prefix} Fetching module index data from CPAN\n" );
    
    require LWP::UserAgent;
    
    my $ua = LWP::UserAgent->new;
    my $response = $ua->get( $moduleindex );
 
    if ($response->is_success) {
        $self->{distindex} = $response->content unless defined $self->{distindex};  
	my @distindex = split /\n/, $self->{distindex};
	for (my $i = 0; $i < @distindex; $i += 2) {
	    $distindex[$i] ||= ''; $distindex[$i + 1] ||= '';
	    $distindex_[$i] = $distindex[$i] . $distindex[$i + 1];
	}
	@distindex = @distindex_;
	for my $dist (@distindex) {
	    $dist ||= '';
	    if ($dist =~ /gz/) {
	        ($distdir, $distcmp) = $dist =~ /^\w+\s+<.*?>.*?<\/.*?>\s+<a href="\.\..*?\/(.*)\/(.*)\-.*tar\.gz".*/;
		$distcmp ||= '';
		
		my ($getcmp) = $self->{getfile} =~ /(.*)\-.*/;
		last if ($getcmp eq $distcmp);
	    }
	}
    } else {
        $self->_report_mail( $response->status_line );
    }
    
    $self->{distdir} = $distdir;
    
    $self->_ftp_initiate;
    
    $self->{ftp}->cwd( "/pub/PAUSE/$distdir" )
      or $self->_report_mail( "Couldn't change working directory: ", $self->{ftp}->message );
      
    $self->{ftp}->get( "$self->{getfile}", "$self->{CONF}{dir}/$self->{getfile}" )
      or $self->_ftp_redo;
	  
    $self->do_verbose( \*STDERR, "$self->{CONF}{prefix} Fetched $self->{getfile} from CPAN\n" ); 
}

sub _report {
    my ($self) = @_;
    
    my $reporter = Test::Reporter->new();
		
    $reporter->debug( $self->{OPT}{verbose} );
	    
    $reporter->from( $self->{CONF}{mail} );
    $reporter->comments( "Automatically processed by $NAME $VERSION" );
    $reporter->distribution( $self->{dist} );	    
    $reporter->grade( $self->_reporter_state() );
	 
    $reporter->send() or $self->_report_mail( $reporter->errstr() );
}
   
sub _user_input {
    my ($self, $cond, $cmd, $msg) = @_; 
    my $input;
    
    do {
        $cmd .= '? ' if $cmd;
	$msg .= ':' unless $msg =~ /:/;
	
        print "$self->{CONF}{prompt} $cmd$msg";
        chomp ($input = <STDIN>);
    } until ($input =~ /^y$/i || $input =~ /^n$/i || $input eq '');
    
    my $matched = 0;
    
    if ($input =~ /$cond/i) {
        $matched = 1;
    }
    
    return ($input, $matched);
}

sub _ftp_initiate {
    my ($self) = @_;

    my $ftp = Net::FTP->new( $self->{CONF}{host}, Debug => $self->{OPT}{verbose} );
    $self->_report_mail( "Couldn't connect to $self->{CONF}{host}: $@") unless ($ftp);
    
    $ftp->login( 'anonymous','anonymous@example.com' )
      or $self->_report_mail( "Couldn't login: ", $ftp->message ); 
  
    $ftp->binary or $self->_report_mail( "Couldn't switch to binary mode: ", $ftp->message );
    
    return $ftp;
}

sub _ftp_redo {
    no strict 'refs';
    my ($self) = @_;
    my $file;

    my @files = $self->{ftp}->ls()
      or $self->_report_mail( "Couldn't get list from /pub/PAUSE/$self->{distdir}: ", $self->{ftp}->message );
      
    my ($getcmp, $gotdist, $version);
    ($getcmp, $version) = $self->{getfile} =~ /(.*)\-(.*)\.tar\.gz/;
      
    for $file (sort {$b cmp $a } @files) {
        if ($file =~ /^$getcmp\-\d+.*$/) {
	    my ($haveversion) = $file =~ /.*\-(.*)\.tar\.gz/;
	    $haveversion ||= '';
            if ($self->{ftp}->get( "$file", "$self->{CONF}{dir}/$file" )) {
                $gotdist = 1;
		$self->{getfile} = $file;
	        last;
	    }
        }
    }
    
    $self->_report_mail( "Couldn't get $file: ", $self->{ftp}->message ) unless $gotdist;
}

sub _is_prereq {
    my ($self) = @_;
    
    if ($self->{install_prereqs}{${$self->{files}}[0]}) {
        return 1;
    }

    return 0;
}

sub _cd_error {
    my ($self) = @_;
   
    #$self->{dist_dir} =~ tr/,//d;
    
    unless (chdir ( $self->{dist_dir} )) {
        warn "--> Could not cd to $self->{dist_dir}, processing next distribution\n";
	return 1;
    }
    
    return 0;
}

sub _process_prereqs {
    no strict 'refs';
    my ($self) = @_;
    
    my $install_prereqs = 0;
    @{$self->{prereqs}} = ();
    
    for my $prereq (sort keys %{$self->{makeargs}->{PREREQ_PM}}) {
        $self->{prereq} = $prereq;
        $self->{version} = $self->{makeargs}{PREREQ_PM}{$prereq} || '0.01';
	
        next if $self->_prereq_sufficient;
	
	$self->do_verbose( \*STDERR, "--> Prerequisite $self->{prereq} not found\n" );
	
	$self->{prereq} =~ s/::/-/g;
	$self->{getfile} = "$self->{prereq}-$self->{version}.tar.gz";
	
	next unless $self->_process( '', "Fetch $self->{getfile} from CPAN? [Y/n]: ", '^n$' ); 
	
	$self->_fetch_prereq;
	
	push( @{$self->{prereqs}}, $self->{getfile} );
	$install_prereqs++;
    }
    
    return $install_prereqs ? 1 : 0;
}

sub _prereq_sufficient {
    no strict 'refs';
    my ($self) = @_;
    $self->{version} ||= '0.01';
    
    my $path = $self->{prereq};
    $path =~ s!::!/!g;
    $path .= '.pm';
    
    for my $inc (@INC) {
        if (-e "$inc/$path") {
	    do eval "require $self->{prereq}";
	    if (${$self->{prereq}.'::VERSION'} < $self->{version}) {
	        return 0;
	    } else {
	        return 1;
	    }
	}
    }
    
    return 0;
}

sub _reporter_state {
    my ($self) = @_;
 
    for my $line ($self->{makeargs}) {
        return 'fail' if $line =~ /failed/;
    }

    return 'pass';
}

sub _report_mail {
    my ($self, @err) = @_;
    
    my $login    = getlogin;
    
    if ($self->{OPT}{verbose}) {
        warn "--> @err";
        warn "--> Reporting error coincidence via mail to $login", '@localhost', "\n";
    }
    
    my $send     = '/usr/sbin/sendmail';
    my $from     = "$NAME $VERSION <$NAME\@localhost>";
    my $to	 = "$login\@localhost";
    my $subject  = "error";
    
    open( my $sendmail, "| $send -t" ) or die "Could not open | to $send: $!\n";
    
    my $selold = select( $sendmail );
    
    print <<"MAIL";
From: $from
To: $to
Subject: $subject

@err
MAIL
    close( $sendmail ) or die "Could not close | to sendmail: $!\n";
    select( $selold );
}

sub _run_makefile {
    my ($self) = @_;
    
    my $MAKEFILE_PL = 'Makefile.PL';
    my $MAKEFILE    = "$self->{dist_dir}/$MAKEFILE_PL";
    my $BUILD_PL    = 'Build.PL';
    my $BUILD       = "$self->{dist_dir}/$BUILD_PL";
    
    if (-e $MAKEFILE) {
        do $MAKEFILE;
    } elsif (-e $BUILD) {
        do $BUILD;      
    } else {
        die "Neither $MAKEFILE nor $BUILD found\n";
    }
}

sub _get_prereqs {
    return { @_ };
}

sub _process {
    my ($self, $cmd, $prompt) = @_;
    
    $prompt  ||= '[Y/n]: ';
    my $cond   = '^n$';
    
    if ($self->{OPT}{interactive}) {        
        my ($input, $matched) = $self->_user_input( $cond, $cmd, $prompt );
    
        if ($matched) {
	    return 0;
	} else {
	    print `$cmd` if $cmd;
	    return 1;
	}
    } 
    else {
        print "$self->{CONF}{prefix} $cmd\n" if $cmd;
	system( $cmd );
	return 1;
    }   
    
    $self->_report_mail( "$self->{dist}: $cmd exited on ", $? & 255, "\n" ) if $?;    
}

1;
__END__

=head1 NAME

CPAN::Tester - Test CPAN contributions and submit reports to cpan-testers@perl.org

=head1 SYNOPSIS

See bin/cpantester.pl therefore.

=head1 DESCRIPTION

This module features automated testing of new contributions that have
been submitted to CPAN and consist of a former package, i.e. have either
a Makefile.PL or a Build.PL and tests.

L<Test::Reporter> is used to send the test reports.

=head1 CONFIGURATION FILE

A .cpantesterrc may be placed in the appropriate home directory.

 # Example
 host		= pause.perl.org
 rdir		= /incoming/
 dir		= /home/user/cpantester
 trackfile	= /home/user/cpantester/track.dat
 mail		= user@host.tld (name)
 rss		= 0
 rss_feed	= http://search.cpan.org/recent.rdf
 
=head1 MAIL

Upon errors, the coincidence will be reported via mail to login@localhost.

=head1 CAVEATS

=head2 Build.PL

Build.PL's will just be handled correctly, in case a traditional Makefile.PL
will be created upon running Build.PL.

=head2 System requirements

Tests on Operating systems besides Linux/UNIX aren't supported yet.

=head1 SEE ALSO

L<Test::Reporter>, L<testers.cpan.org>

=cut
