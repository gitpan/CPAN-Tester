#! /usr/local/bin/perl

use strict;
use warnings;
use CPAN::Tester;

use Test::More tests => 2;

BEGIN {
    my $PACKAGE = 'CPAN::Tester';
    use_ok( $PACKAGE );
    require_ok( $PACKAGE );
}
