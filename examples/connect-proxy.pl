#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

use strict;
use warnings;

# Use bundled libraries
use FindBin;
use lib "$FindBin::Bin/../lib";

# Cheating in a fake fight. That's low.
use Mojo::IOLoop;

# The loop
my $loop = Mojo::IOLoop->new;

# Connection buffer
my $c = {};

# Minimal connect proxy server to test TLS tunneling
$loop->listen(
    port    => 3000,
    read_cb => sub {
        my ($loop, $client, $chunk) = @_;
        $c->{$client}->{client} ||= '';
        $c->{$client}->{client} .= $chunk;
        if (my $server = $c->{$client}->{connection}) {
            $loop->writing($server);
            return;
        }
        if ($c->{$client}->{client} =~ /\x0d?\x0a\x0d?\x0a$/) {
            my $buffer = delete $c->{$client}->{client};
            if ($buffer =~ /CONNECT (\S+):(\d+)?/) {
                my $server = $loop->connect(
                    address    => $1,
                    port       => $2 || 80,
                    connect_cb => sub {
                        my ($loop, $server) = @_;
                        $c->{$client}->{connection} = $server;
                        $c->{$client}->{server} = "HTTP/1.1 200 OK\x0d\x0a"
                          . "Connection: keep-alive\x0d\x0a\x0d\x0a";
                        $loop->writing($client);
                    },
                    error_cb => sub {
                        shift->drop($client);
                        delete $c->{$client};
                    },
                    read_cb => sub {
                        my ($loop, $server, $chunk) = @_;
                        $c->{$client}->{server} ||= '';
                        $c->{$client}->{server} .= $chunk;
                        $loop->writing($client);
                    },
                    write_cb => sub {
                        my ($loop, $server) = @_;
                        $loop->not_writing($server);
                        return delete $c->{$client}->{client};
                    }
                );
            }
            else { $loop->drop($client) }
        }
    },
    write_cb => sub {
        my ($loop, $client) = @_;
        $loop->not_writing($client);
        return delete $c->{$client}->{server};
    },
    error_cb => sub {
        my ($self, $client) = @_;
        shift->drop($c->{$client}->{connection})
          if $c->{$client}->{connection};
        delete $c->{$client};
    }
) or die "Couldn't create listen socket!\n";

print <<'EOF';
Starting connect proxy on port 3000.
For testing use something like "HTTPS_PROXY=https://127.0.0.1:3000".
EOF

# Start loop
$loop->start;

1;
