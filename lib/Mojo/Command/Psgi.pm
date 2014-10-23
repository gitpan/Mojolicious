# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojo::Command::Psgi;

use strict;
use warnings;

use base 'Mojo::Command';

use Mojo::Server::PSGI;

use Getopt::Long 'GetOptions';

__PACKAGE__->attr(description => <<'EOF');
Start application with PSGI backend.
EOF
__PACKAGE__->attr(usage => <<"EOF");
usage: $0 psgi [OPTIONS]

These options are available:
  --reload   Automatically reload application when the source code changes.
EOF

# D’oh.
sub run {
    my $self = shift;
    my $psgi = Mojo::Server::PSGI->new;

    # Options
    @ARGV = @_ if @_;
    GetOptions(reload => sub { $psgi->reload(1) });

    # Return app callback
    return sub { $psgi->run(@_) };
}

1;
__END__

=head1 NAME

Mojo::Command::Psgi - PSGI Command

=head1 SYNOPSIS

    use Mojo::Command::Psgi;

    my $psgi = Mojo::Command::Psgi->new;
    my $app = $psgi->run(@ARGV);

=head1 DESCRIPTION

L<Mojo::Command::Psgi> is a command interface to L<Mojo::Server::PSGI>.

=head1 ATTRIBUTES

L<Mojo::Command::Psgi> inherits all attributes from L<Mojo::Command> and
implements the following new ones.

=head2 C<description>

    my $description = $psgi->description;
    $psgi           = $psgi->description('Foo!');

Short description of this command, used for the command list.

=head2 C<usage>

    my $usage = $psgi->usage;
    $psgi     = $psgi->usage('Foo!');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojo::Command::Psgi> inherits all methods from L<Mojo::Command> and
implements the following new ones.

=head2 C<run>

    my $app = $psgi->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
