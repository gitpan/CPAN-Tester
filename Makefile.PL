use ExtUtils::MakeMaker;
WriteMakefile(
    NAME         => 'CPAN::Tester',
    VERSION_FROM => 'lib/CPAN/Tester.pm',
    PREREQ_PM    => { Carp 		  => 0,
                      ExtUtils::MakeMaker => 0,
                      File::Slurp 	  => 0,
		      Getopt::Long 	  => 0,
		      Net::FTP 		  => 0,
		      Test::Reporter 	  => 0 },
    ($] >= 5.005 
      ? (ABSTRACT_FROM => 'lib/CPAN/Tester.pm') : ()
    ),
);
