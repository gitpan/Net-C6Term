package Net::C6Term;

use 5.008;
use strict;
use warnings;

use IPC::Run();

our $VERSION = 0.10;

=head1 NAME

Net::C6Term - Interface to the C6Term protocol, which allows to connect to C6 servers

=head1 SYNOPSIS

use strict;
use Net::C6Term;

my $c6 = Net::C6Term->new();

$c6->add_handler(200, \&on_connect);
$c6->add_handler('default', \&on_default);

$c6->send_event('connect', 'c6login.tin.it', 4800);

$c6->start();

$c6->finish();

=head1 DESCRIPTION

Net::C6Term provides an interface to the I<c6term> software written by Rodolfo
Giacometti, which allows you to connect to a C6 server (C6 is an Italian ICQ-like
instant messaging system). I<c6term>, along with C6 protocol specifications
and other related software and documentation, can be found at the Open C6
project home page, at L<http://openc6.extracon.it> . Please read the I<c6term>
documentation to find out how to connect and how to send commands to the
C6 server.

=cut

=head1 CONSTRUCTOR

=over 4

=item *

new([command])

Creates a new Net::C6Term object, which represent a single connection (that is,
a C<fork()> with IPC communication) to the I<c6term> external program. You can
supply an optional command, which will tell the path and filename of the I<c6term>
program. If none is provided, C<./c6term> will be used.

=cut

sub new {
    my $invocant = shift;
    my $class = ref($invocant) || $invocant;
    my $self = { };

    $self->{'command'} = shift || './c6term';
    
    # Initialize IO channels
    $self->{'c6in'} = '';
    $self->{'c6out'} = '';
    $self->{'c6err'} = '';

    # Spawn c6term
    my @cmd = ($self->{'command'});
    $self->{'c6t'} = IPC::Run::start \@cmd, \$self->{'c6in'}, \$self->{'c6out'}, \$self->{'c6err'};
    if (!$self->{'c6t'}) {
        return undef;
    }
    if ($self->{'c6err'}) {
	warn $self->{'c6err'};
	$self->{'c6err'} = '' ;
    }

    # Initialize variables
    $self->{'evno'} = 0;
    $self->{'strstr'} = '';
    $self->{'logged'} = 0;
    $self->{'eventhandlers'} = {};

    bless($self, $class);
    return $self;
}

=head1 METHODS
    
All of the following methods are instance methods: you must call them on a
Net::C6Term object you created.

=over 4

=item *

add_handler(eventcode, subref)

Sets an handler function for a specific event of the I<c6term> program
(that is, of the C6 server you are connected to). You need to provide
the numeric event code (see the I<c6term> documentation for more information
about codes, and the EVENTS sections for the C6Term.pm additional ones),
and a reference to the sub that you want to use to handle that event.
If you provide I<default> as the event code, the passed sub will be used
for all events for which you've defined no specific handler.
A reference to the C6Term object will be passed to the sub.

=cut

sub add_handler {
    my $self = shift;
    my ($ecode, $subref) = @_;
    
    $self->{'eventhandlers'}{$ecode} = $subref;
}

=item *

send_event(command [,param, ...])

Queues an event (that is, a command) for sending to I<c6term>. The command
is in string format, see the I<c6term> documentation for information on
available commands. There is an optional number of parameters, which you
may provide depending on the command you are issuing.

Note that calling this method doesn't actually send that event to the
server, unless the method C<start()> was called before. To actually send
you event you'll need a call to C<do_one_loop()>.

=cut

sub send_event {
    my $self = shift;
    my $command = shift;
    my @params = @_;

    $self->{'c6in'} .= join(" ", $command, @params, "\n");
}

=item *

do_one_loop()

This method fowards any queued command to I<c6term>, and fetches any queued
incoming event, calling the defined event handlers (see C<add_handler()>.
You'll probably need to call this method quite often in your software to be
able process incoming events. This method is non blocking, so if there are
no incoming events it will just return instead of waiting indefinitely.

Returns 0 if the child died prematurely, 1 in all other cases.

=cut

sub do_one_loop {
    my $self = shift;

    if ($self->{'c6t'}->pumpable()) {
        
        # Do input and output
        $self->{'c6t'}->pump_nb();
        if ($self->{'c6err'}) {
            warn $self->{'c6err'};
            $self->{'c6err'} = '' ;
        }

        # There might be 0, 1 or more events from c6term
        my @events = split(/\n/, $self->{'c6out'});

        foreach my $e(@events) {        

            if ($e =~ /^(\d{3}) (.*)\n{0,1}$/) {

                $self->{'evno'} = $1;
                $self->{'evstr'} = $2;
            
            } else {

                $self->{'evno'} = 3000;
                $self->{'evstr'} = 'unknown c6term response ($e)';

            }

            # If an event handler is defined, we call it
            if ($self->{'eventhandlers'}{$self->{'evno'}}) {
                &{$self->{'eventhandlers'}{$self->{'evno'}}} ($self);
    
            # Otherwise we try with the generic handler, if defined
            } elsif ($self->{'eventhandlers'}{'default'}) {
                &{$self->{'eventhandlers'}{'default'}} ($self);
            }
            
        }

        $self->{'c6out'} = '';
        return 1;

    } else {

        $self->{'evno'} = 3001;
        $self->{'evstr'} = 'c6term child died prematurely';
        return 0;
        
    }
}

=item *

start()

Starts a loop which only ends when the I<c6term> child terminates (or dies
prematurely). It's actually a continuos call to C<do_one_loop()>, which
ends when that method returns 0.

You can use start() if you've got a very simple application which needs to
almost do nothing except wait for C6 events and, upon receipt of them, do
something and/or send other events.

=cut

sub start {
    my $self = shift;
    
    while ($self->do_one_loop()) { }
}

=item *

finish()

Terminated the forked I<c6term> child. You'd better logout (using the
appropriate command) from the C6 server before calling this. If something
goes wrong when terminating I<c6term>, your program will C<die()>.

=cut

sub finish {
    my $self = shift;

    $self->{'c6in'} = "quit\n";
    $self->{'c6t'}->finish or die "serious problems closing c6term.";
}

=item *

evstr()

Returns the number of the latest event processed by do_one_loop.
You should call this method from inside your handler function to get information
about what the server replied you.

=cut

sub evno {
    my $self = shift;

    return $self->{'evno'};
}

=item *

evstr()

Returns a string with the content of the latest event processed by do_one_loop.
You should call this method from inside your handler function to get information
about what the server replied you.

=cut

sub evstr {
    my $self = shift;

    return $self->{'evstr'};
}

=head1 EVENTS

All the events are the ones reported in the I<c6term> documentation, plus a
couple specific to C6Term.pm.

=over 4

=item *

3000 unknown c6term response (I<response>)

This event occurs in case of an unknown (malformed) response from the I<c6term>
program. The response itself is provided between parentheses.

=item *

3001 c6term child died prematurely

If, for some reason, the forked I<c6term> program dies prematurely, this event
is returned.

=head1 TODO

=over 4

=item *

Add better error handling in C<finish()>: now it just dies if something goes
wrong when terminating the forked child. Elegant, uh? :-)

=item *

Add methods to send events in without needing to know the c6term commands
(i.e. connect(), login(), ...).

=item *

Rely on IPC::Socket3 instead of IPC::Run.

=head1 COPYRIGHT

Copyright 2003, Michele Beltrame <mb@italpro.net> - L<http://www.italpro.net/mb/>

This library is free software; you can redistribute it and/or modify it
under the GNU General Public License.

=cut

1;
