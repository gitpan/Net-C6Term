use 5.008;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'Net::C6Term',
    'VERSION_FROM'	=> 'lib/Net/C6Term.pm', # finds $VERSION
    'PREREQ_PM'		=> {
	IPC::Run => 0,
      },
      ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM => 'lib/Net/C6Term.pm', # retrieve abstract from module
       AUTHOR        => 'Michele Beltrame <mb@italpro.net>') : ()),
);
