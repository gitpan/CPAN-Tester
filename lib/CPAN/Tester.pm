package CPAN::Tester;

our $VERSION = '0.01_11';
our $NAME = 'CPAN::Tester';

@EXPORT_OK = qw(new poll test);

use strict;
use warnings;
no warnings qw(redefine);
use base qw(Exporter);
 
use Carp 'croak';
use Email::Send;
use ExtUtils::MakeMaker;
use File::Slurp;
use Net::FTP;
use Parse::CPAN::Packages;
use Test::Reporter;

$| = 1;

our $CONFIG = '.cpantesterrc';

sub new {
    my ($self, $conf, $opt) = @_;  
    my $class = ref( $self ) || $self;
    
    return bless( blessed_conf( $conf, $opt ), $class );
}

sub blessed_conf {
    my ($conf, $opt) = @_;
    
    my %blessed = (
	    DEF     =>	
	    {
		    build_pl	    => 'Build.PL',
		    makefile_pl     => 'Makefile.PL',
		    pkgs_details    => '02packages.details.txt.gz',
		    pause_root      => '/pub/PAUSE/',
	    },	
	    CONF    =>	$conf,
	    OPT     =>	$opt,	
    );
    
    return \%blessed; 
}

sub test {
    no strict 'refs';
    my ($self) = @_;
    
    open( my $track, ">>$self->{CONF}{trackfile}" ) 
      or $self->_report_mail( "Couldn't open $self->{CONF}{trackfile} for writing: $!\n " );
    
    $self->fetch;
    $self->read_track;
    
    while (@{$self->{files}}) {
        if ($self->{got_file}->{${$self->{files}}[0]} || ${$self->{files}}[0] !~ /tar.gz$/) {
            shift @{$self->{files}};
	    next;
	}
	
	($self->{dist}) = ${$self->{files}}[0] =~ /(.*)\.tar.gz$/;
	
	$self->_ftp_initiate unless defined $self->{ftp};
	
	unless ($self->_test) {
	    $self->{got_file}{${$self->{files}}[0]} = 1;
	    print $track "${$self->{files}}[0]\n";
	}
    }
	
    close( $track ) 
      or $self->_report_mail( "Couldn't close $self->{CONF}{trackfile}: $!\n" );

    $self->{ftp}->quit;
}

sub poll {
    my ($self) = @_;
    
    for (;;) { 
        my $string = 'second(s) until poll';
	    my $oldlen = 0;
	    
	    $self->test;
	    
	    for (my $sec = $self->{OPT}{poll}; $sec >= 1; $sec--) {
	        $self->do_verbose( \*STDERR, "$self->{CONF}{prefix} $sec " );
		
                my $fulllen = (length( $self->{CONF}{prefix} ) + 1 + length ( $sec ) + 1 + length( $string ));
	        # In case we have no old length, store current length (avoids warnings)
	        $oldlen = $fulllen unless $oldlen;
	        # Calculate how many spaces need to be erased
	        my $blank = $oldlen - $fulllen;
	        # Store old length
	        $oldlen = $fulllen;
		
	        print( $string, ' ' x $blank, "\b" x ($fulllen + $blank) ) 
	          if ($self->{OPT}{verbose} && $sec != 1);
	    
	        $blank = 0;
		
	        sleep 1;
	    }
		
        $self->do_verbose( \*STDERR, "\n$self->{CONF}{prefix} Polling\n" );
    }
}

sub fetch {
    my ($self) = @_;
    my @files;
    
    $self->_ftp_initiate;
      
    if ($self->{CONF}{rss}) {    
	require LWP::UserAgent;
 
        my $ua = LWP::UserAgent->new;
        my $response = $ua->get( $self->{CONF}{rss_feed} );
 
        if ($response->is_success) {
            @files = $response->content =~ /<title>(.*?)<\/title>/gm;
	    @files = map { $_ . '.tar.gz' } @files;  
        } else {
            $self->_report_mail( $response->status_line );
        }
        
	$self->{ftp}->cwd( $self->{CONF}{rdir} )
          or $self->_report_mail( "Couldn't change working directory: ", $self->{ftp}->message ); 
    } 
    else {
        $self->{ftp}->cwd( $self->{CONF}{rdir} )
          or $self->_report_mail( "Couldn't change working directory: ", $self->{ftp}->message );
        
        @files = $self->{ftp}->ls()
          or $self->_report_mail( "Couldn't get list from $self->{CONF}{rdir}: ", $self->{ftp}->message );
    }
   
    @{$self->{files}} = sort @files[ 2 .. $#files ];
}

sub read_track {
    my ($self) = @_;   

    my $track = read_file( $self->{CONF}{trackfile} ) 
      or die "Could not read $self->{CONF}{trackfile}: $!\n";
      
    %{$self->{got_file}} = map { $_ => 1 } split /\n/, $track;
}

sub weed_out_track {
    my ($self) = @_;
    my %file;
    
    my $trackf = read_file( $self->{CONF}{trackfile} ) 
      or die "Could not open $self->{CONF}{trackfile} for reading: $!\n";
    
    my @track = split /\n/, $trackf;
    
    # Establish FTP-connection to PAUSE's incoming directory
    # and reduce the trackfile accordingly to existing submissions.
    $self->{ftp}->cwd( $self->{CONF}{rdir} )
      or $self->_report_mail( "Couldn't change working directory: ", $self->{ftp}->message );
        
    my @remotefiles = $self->{ftp}->ls()
      or $self->_report_mail( "Couldn't get list from $self->{CONF}{rdir}: ", $self->{ftp}->message );
      
    my %remotegot = map { $_ => 1 } @remotefiles;
    @track = grep { $remotegot{$_} } @track;

    # Remove entries, that exist twice. Unneeded?
    for (my $i = 0; $i < @track;) {
        if ($file{$track[$i]}) {
            splice( @track, $i, 1 );
            next;
        }
        $file{$track[$i]} = 1;
        $i++;
    }
    
    @{$self->{track}} = sort @track;
    
    open( my $track, ">$self->{CONF}{trackfile}" ) 
      or die "Could not open $self->{CONF}{trackfile} for writing: $!\n";
      
    print $track "@{$self->{track}}\n";
    
    close( $track ) 
      or die "Could not close $self->{CONF}{trackfile}: $!\n";
}

sub do_verbose {
    no strict 'refs';
    my ($self, $out, @err) = @_;
    
    $out->print( @err ) if $self->{OPT}{verbose};
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
	
    local *ExtUtils::MakeMaker::WriteMakefile = \&_get_makeargs;
    $self->{makeargs} = $self->_run_makefile;
	
    my $install_prereqs = 0;
	
    if ($self->_process_prereqs) {
        unshift( @{$self->{files}}, sort keys %{$self->{prereqs_get}} );
        # Flaq prereqs as existing, in order to skip fetching subsequently
        %{$self->{prereqs_installed}} = %{$self->{prereqs_get}};
        return 1;
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

sub _process_prereqs {
    no strict 'refs';
    my ($self) = @_;
    my (%prereqs);
    
    if (scalar %{$self->{makeargs}{PREREQ_PM}}) {
        %{$self->{prereqs}} = ();
    
        for my $prereq (sort keys %{$self->{makeargs}{PREREQ_PM}}) {
            $prereqs{$prereq} = $self->{makeargs}{PREREQ_PM}{$prereq} || '0.01';
        }
        $self->{prereqs} = \%prereqs;
    
        $self->_check_prereqs_sufficient;
		
        $self->do_verbose( \*STDERR, "$self->{CONF}{prefix} Prerequisite(s) not found:\n" );
        for my $prereq (sort keys %{$self->{prereqs}}) {
            $self->do_verbose( \*STDERR, "\t* $prereq\n" );
        }
    
        $self->_fetch_pkgs_detail;
    
        for my $prereq (sort keys %{$self->{prereqs}}) {
            my $version = $self->{prereqs}{$prereq};
            $prereq =~ s/::/-/g;
            my $prereq_version = "$prereq-$version";
            next unless $self->_process( '', "Fetch $prereq_version from CPAN? [Y/n]: ", '^n$' );
            my $prereq_full = $prereq_version . '.tar.gz';
            $self->{prereqs_get}{$prereq_full} = 1;
        }
    
        $self->_fetch_prereqs;
    
        return scalar keys %{$self->{prereqs_get}} ? 1 : 0;
    }
    
    return 0;
}

sub _check_prereqs_sufficient {
    no strict 'refs';
    my ($self) = @_;
    
    # Key: prerequisite, value: version
    for my $prereq (sort keys %{$self->{prereqs}}) {
        # Default version to 0.01, if none set
        $self->{prereqs}{$prereq} ||= '0.01';
	
        my $prereq_path = $prereq;
        $prereq_path =~ s!::!/!g;
        $prereq_path .= '.pm';
    
        for my $inc (@INC) {
            if (-e "$inc/$prereq_path") {
                do eval "require $prereq";
                die $@ if $@;
                my $local_prereq_var = ${$prereq.'::VERSION'};
                # Abandon "Argument "version" isn't numeric in numeric gt"
                if ($local_prereq_var =~ /_/) {
                    $local_prereq_var =~ s/(.*?)_.*/$1/;
                }
                # Compare local prereq version against required one
                if ($local_prereq_var > $self->{prereqs}{$prereq}) {
                    delete $self->{prereqs}{$prereq};
                }
            }
        }
    }
}

sub _fetch_prereqs {
    my ($self) = @_;    
    my ($distcmp, $prereq_dir, @distindex_);
    
    my $p = Parse::CPAN::Packages->new( $self->{dir_pkgs_details} );
    my @dists = $p->distributions;

    for my $d (sort @dists) {
        my $prefix       = $d->prefix;
        my $prereq_have  = $d->dist;
        ($prereq_dir)    = $prefix =~ m!(\w+?\/\w+?/\w+?/).*!;
	
        next unless ($prereq_have && $prereq_dir);
	
        # Key: archive filename, Value: 1
        for my $prereqget (sort keys %{$self->{prereqs_get}}) {
            my ($prereq_get) = $prereqget =~ /(.*)\-.*/;
	    if ($prereq_get eq $prereq_have) {
	        $prereq_dir = "authors/id/$prereq_dir";
	        $self->{prereqs_dir}{$prereqget} = $prereq_dir;
	    }
        }
    }
    
    $self->{distdir} = $prereq_dir;
    
    $self->_ftp_initiate unless $self->{ftp};
    
    # Key: archive filename, Value: prerequisite directory
    for my $prereq (sort keys %{$self->{prereqs_dir}}) {
        $self->{prereq} = $prereq;
        my $prereq_dir  = $self->{prereqs_dir}{$self->{prereq}};     
    
        $self->{ftp}->cwd( "/pub/PAUSE/$prereq_dir" )
          or $self->_report_mail( "Couldn't change working directory: ", $self->{ftp}->message );
      
        $self->{ftp}->get( $self->{prereq}, "$self->{CONF}{dir}/$self->{prereq}" )
          or $self->_ftp_redo;
      
        if ($prereq ne $self->{prereq}) {
            delete $self->{prereqs_get}{$prereq};
            $self->{prereqs_get}{$self->{prereq}} = 1;
        }
	  
        $self->do_verbose( \*STDERR, "$self->{CONF}{prefix} Fetched $self->{prereq} from CPAN\n" ); 
    }
}

sub _fetch_pkgs_detail {
    my ($self) = @_;
    
    $self->do_verbose( \*STDERR, "$self->{CONF}{prefix} Fetching ", $self->{DEF}{pkgs_details}, " from CPAN\n" );

    $self->{dir_pkgs_details} = "$self->{CONF}{dir}/" . $self->{DEF}{pkgs_details};

    $self->_ftp_initiate unless $self->{ftp};
    
    $self->{ftp}->cwd( $self->{DEF}{pause_root} . 'modules' )
      or $self->_report_mail( "Couldn't change working directory: ", $self->{ftp}->message );
      
    $self->{ftp}->get( $self->{DEF}{pkgs_details}, $self->{dir_pkgs_details} )
      or croak "Could not get ", $self->{DEF}{pkgs_details}, " : $!\n";
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

sub _user_input {
    my ($self, $cond, $cmd, $msg) = @_; 
    my $input;
    
    do {
        $cmd .= '? ' if $cmd;
        $msg .= ':' unless $msg =~ /:/;
	
        print "$self->{CONF}{prompt} $cmd$msg";
        chomp ($input = <STDIN>);
    } until ($input =~ /^y$/i || $input =~ /^n$/i || $input eq '');
    
    return ($input, ($input =~ /$cond/i) ? 1 : 0);
}

sub _report {
    my ($self) = @_;
    
    my $reporter = Test::Reporter->new
    (
    	debug           => $self->{OPT}{very_verbose},
        from            => $self->{CONF}{mail},
        comments        => "Automatically processed by $NAME $VERSION",
        distribution    => $self->{dist},
        grade           => $self->_reporter_state(),
    );
	 
    $reporter->send() or $self->_report_mail( $reporter->errstr() );
}

sub _ftp_initiate {
    my ($self) = @_;

    $self->{ftp} = Net::FTP->new( $self->{CONF}{host}, Debug => $self->{OPT}{very_verbose} );
    $self->_report_mail( "Couldn't connect to $self->{CONF}{host}: $@") unless $self->{ftp};
    
    $self->{ftp}->login( 'anonymous','anonymous@example.com' )
      or $self->_report_mail( "Couldn't login: ", $self->{ftp}->message ); 
  
    $self->{ftp}->binary 
      or $self->_report_mail( "Couldn't switch to binary mode: ", $self->{ftp}->message );
}

sub _ftp_redo {
    no strict 'refs';
    my ($self) = @_;
    my $file;

    my @files = $self->{ftp}->ls()
      or $self->_report_mail( "Couldn't get list from /pub/PAUSE/$self->{distdir}: ", $self->{ftp}->message );
      
    my ($getcmp, $gotdist, $version);
    ($getcmp, $version) = $self->{prereq} =~ /(.*)\-(.*)\.tar\.gz/;
      
    for $file (sort {$b cmp $a } @files) {
        if ($file =~ /^$getcmp\-\d+.*$/) {
            if ($self->{ftp}->get( $file, "$self->{CONF}{dir}/$file" )) {
                $gotdist = 1;
                $self->{prereq} = $file;
                last;
            }
        }
    }
    
    $self->_report_mail( "Couldn't get $file: ", $self->{ftp}->message ) unless $gotdist;
}

sub _is_prereq {
    my ($self) = @_;
    
    if ($self->{prereqs_installed}{${$self->{files}}[0]}) {
        return 1;
    }

    return 0;
}

sub _cd_error {
    my ($self) = @_;
    
    unless (chdir ( $self->{dist_dir} )) {
        warn "$self->{CONF}{prefix} Could not cd to $self->{dist_dir}, processing next distribution\n";
        return 1;
    }
    
    return 0;
}

sub _run_makefile {
    my ($self) = @_;
    
    my $MAKEFILE_PL = $self->{DEF}{makefile_pl};
    my $MAKEFILE    = "$self->{dist_dir}/$MAKEFILE_PL";
    my $BUILD_PL    = $self->{DEF}{build_pl};
    my $BUILD       = "$self->{dist_dir}/$BUILD_PL";
    
    if (-e $MAKEFILE) {
        do $MAKEFILE;
    } elsif (-e $BUILD) {
        do $BUILD;      
    } else {
        die "Neither $MAKEFILE nor $BUILD found\n";
    }
}

sub _get_makeargs {
    return { @_ };
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
        warn "$self->{CONF}{prefix} @err";
        warn "$self->{CONF}{prefix} Reporting error coincidence via mail to $login", '@localhost', "\n";
    }
    
    my $host	 = 'localhost';
    
    my $from     = "$NAME $VERSION <$NAME\@localhost>";
    my $to       = "$login\@localhost";
    my $subject  = "error";
    
    send SMTP => <<MESSAGE, $host;
From: $from
To: $to
Subject: $subject

@err
MESSAGE

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
a Makefile.PL or a Build.PL and tests defined.

L<Test::Reporter> is used to send the test reports.

=head1 CONFIGURATION FILE

A .cpantesterrc may be placed in the appropriate home directory.

 # Example
 host		= pause.perl.org
 rdir		= /incoming
 dir		= /home/user/cpantester
 trackfile	= /home/user/cpantester/track.dat
 mail		= user@host.tld (name)
 rss		= 1
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
