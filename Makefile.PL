use ExtUtils::MakeMaker;
WriteMakefile(
    NAME         => 'CPAN::Tester',
    VERSION_FROM => 'lib/CPAN/Tester.pm',
    PREREQ_PM    => { Carp 		    => 0,
                      Email::Send           => 1.46,
                      ExtUtils::MakeMaker   => 0,
                      File::Slurp 	    => 9999.07,
		      Getopt::Long 	    => 0,
		      Net::FTP 		    => 0,
		      Parse::CPAN::Packages => 2.24,
		      Test::Reporter 	    => 1.27 },
    ($] >= 5.005 
      ? (ABSTRACT_FROM => 'lib/CPAN/Tester.pm') : ()
    ),
);
