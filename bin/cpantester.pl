#! /usr/bin/perl

use strict;
use warnings;
use CPAN::Tester;
use File::Slurp;
use Getopt::Long;

my ($conf, $opt) = parse_args();
my $ct = CPAN::Tester->new( $conf, $opt );
    
$ct->weed_out_track;
    
unless ($ct->{OPT}{poll}) {
    $ct->do_verbose( \*STDERR, "--> Mode: non-polling, 1\n" );
    $ct->test;
} else {
    $ct->do_verbose( \*STDERR, "--> Mode: polling, 1 <--> infinite\n" );
    $ct->poll;
}

exit; 

sub parse_args {
    my (%conf);
    
    $Getopt::Long::autoabbrev = 0;
    $Getopt::Long::ignorecase = 0; 

    GetOptions(\my %opt, 'h', 'i', 'p=i', 'v', 'V') or usage();
    
    usage()   if $opt{h};
    version() if $opt{V};
        
    my $login   = getlogin;
    my $homedir = $login =~ /(root)/ ? "/$1" : "/home/$login";
    
    my $conf_text = read_file( "$homedir/.cpantesterrc" )
      or die "Could not open $homedir/.cpantesterc: $!\n";
    %conf = $conf_text =~ /^([^=]+?)\s+=\s+(.+)$/gm;
    
    $conf{prefix}      = '-->';
    $conf{prompt}      = '#';
    
    $opt{interactive}  = $opt{i} ? 1 : 0;
    $opt{poll}         = $opt{p} ? $opt{p} : 0;
    $opt{verbose}      = $opt{v} ? 1 : 0;
    
    return (\%conf, \%opt);
}

sub usage {
    my ($err_msg) = @_;
    $err_msg ||= '';
    $err_msg .= "\n" if $err_msg;
    
    print <<USAGE;
usage: $0 [ -h | -V ] [ -i | -p intervall | -v ]
  -h			this help screen
  -i			interactive (defies -v) 
  -p intervall		run in polling mode 
  			    intervall: seconds to wait until polling
  -v			verbose
  -V			version info
USAGE

    exit;
}

sub version {
    print "  $CPAN::Tester::NAME $CPAN::Tester::VERSION\n";
    exit;
}

__END__

=head1 NAME

cpantester - Run CPAN::Tester

=head1 SYNOPSIS

 usage: cpantester.pl [ -h | -V ] [ -i | -p intervall | -v ]

=head1 OPTIONS

   -h			this help screen
   -i			interactive (defies -v)
   -p intervall		run in polling mode 
  			    intervall: seconds to wait until poll again
   -v			verbose
   -V			version info

=cut
