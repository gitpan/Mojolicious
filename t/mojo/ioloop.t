#!/usr/bin/env perl
use Mojo::Base -strict;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_IOWATCHER} = 'Mojo::IOWatcher';
}

use Test::More tests => 28;

# "Marge, you being a cop makes you the man!
#  Which makes me the woman, and I have no interest in that,
#  besides occasionally wearing the underwear,
#  which as we discussed, is strictly a comfort thing."
use_ok 'Mojo::IOLoop';
use_ok 'Mojo::IOLoop::Client';
use_ok 'Mojo::IOLoop::Delay';
use_ok 'Mojo::IOLoop::Server';
use_ok 'Mojo::IOLoop::Stream';

# Custom watcher
package MyWatcher;
use Mojo::Base 'Mojo::IOWatcher';

package main;

# Watcher detection
$ENV{MOJO_IOWATCHER} = 'MyWatcherDoesNotExist';
my $loop = Mojo::IOLoop->new;
is ref $loop->iowatcher, 'Mojo::IOWatcher', 'right class';
$ENV{MOJO_IOWATCHER} = 'MyWatcher';
$loop = Mojo::IOLoop->new;
is ref $loop->iowatcher, 'MyWatcher', 'right class';

# Double start
my $error;
Mojo::IOLoop->defer(
  sub {
    eval { Mojo::IOLoop->start };
    $error = $@;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
like $error, qr/^Mojo::IOLoop already running/, 'right error';

# Ticks
my $ticks = 0;
my $id = $loop->recurring(0 => sub { $ticks++ });

# Timer
my $flag = 0;
my $flag2;
$loop->timer(
  1 => sub {
    my $self = shift;
    $self->timer(
      1 => sub {
        shift->stop;
        $flag2 = $flag;
      }
    );
    $flag = 23;
  }
);

# HiRes timer
my $hiresflag = 0;
$loop->timer(0.25 => sub { $hiresflag = 42 });

# Start
$loop->start;

# Timer
is $flag, 23, 'recursive timer works';

# HiRes timer
is $hiresflag, 42, 'hires timer';

# Another tick
$loop->one_tick;

# Ticks
ok $ticks > 2, 'more than two ticks';

# Run again without first tick event handler
my $before = $ticks;
my $after  = 0;
$loop->recurring(0 => sub { $after++ });
$loop->drop($id);
$loop->timer(1 => sub { shift->stop });
$loop->start;
$loop->one_tick;
ok $after > 1, 'more than one tick';
is $ticks, $before, 'no additional ticks';

# Recurring timer
my $count = 0;
$loop->recurring(0.5 => sub { $count++ });
$loop->timer(3 => sub { shift->stop });
$loop->start;
$loop->one_tick;
ok $count > 3, 'more than three recurring events';

# Handle
my $port = Mojo::IOLoop->generate_port;
my $handle;
$loop->server(
  port => $port,
  sub {
    my ($loop, $stream) = @_;
    $handle = $stream->handle;
    $loop->stop;
  }
);
$loop->client((address => 'localhost', port => $port) => sub { });
$loop->start;
isa_ok $handle, 'IO::Socket', 'right reference';

# Stream
$port = Mojo::IOLoop->generate_port;
my $buffer = '';
Mojo::IOLoop->server(
  port => $port,
  sub {
    my ($loop, $stream, $id) = @_;
    $buffer .= 'accepted';
    $stream->on(
      read => sub {
        my ($stream, $chunk) = @_;
        $buffer .= $chunk;
        return unless $buffer eq 'acceptedhello';
        $stream->write('world');
        $stream->emit('close');
      }
    );
  }
);
my $delay = Mojo::IOLoop->delay;
$delay->begin;
Mojo::IOLoop->client(
  {port => $port} => sub {
    my ($loop, $stream, $error) = @_;
    $delay->end($stream);
    $stream->on(close => sub { $buffer .= 'should not happen' });
    $stream->on(error => sub { $buffer .= 'should not happen either' });
  }
);
$handle = $delay->wait->steal_handle;
my $stream = Mojo::IOLoop->singleton->stream_class->new($handle);
$id = Mojo::IOLoop->stream($stream);
$stream->on(close => sub { Mojo::IOLoop->stop });
$stream->on(read => sub { $buffer .= pop });
$stream->write('hello');
ok Mojo::IOLoop->stream($id), 'stream exists';
Mojo::IOLoop->start;
ok !Mojo::IOLoop->stream($id), 'stream does not exist anymore';
is $buffer, 'acceptedhelloworld', 'right result';

# Dropped listen socket
$port = Mojo::IOLoop->generate_port;
$id = $loop->server({port => $port} => sub { });
my $connected;
$loop->client(
  {port => $port} => sub {
    my ($loop, $stream) = @_;
    $loop->drop($id);
    $loop->stop;
    $connected = 1;
  }
);
like $ENV{MOJO_REUSE}, qr/(?:^|\,)$port\:/, 'file descriptor can be reused';
$loop->start;
unlike $ENV{MOJO_REUSE}, qr/(?:^|\,)$port\:/, 'environment is clean';
ok $connected, 'connected';
$error = undef;
$loop->client(
  (port => $port) => sub {
    shift->stop;
    $error = pop;
  }
);
$loop->start;
ok $error, 'has error';

# Dropped connection
$port = Mojo::IOLoop->generate_port;
my ($server_close, $client_close);
Mojo::IOLoop->server(
  (port => $port) => sub {
    my ($loop, $stream) = @_;
    $stream->on(close => sub { $server_close++ });
  }
);
$id = Mojo::IOLoop->client(
  (port => $port) => sub {
    my ($loop, $stream) = @_;
    $stream->on(close => sub { $client_close++ });
    $loop->drop($id);
  }
);
Mojo::IOLoop->timer('0.5' => sub { shift->stop });
Mojo::IOLoop->start;
is $server_close, 1, 'server emitted close event once';
is $client_close, 1, 'client emitted close event once';

# Defaults
is Mojo::IOLoop::Client->new->iowatcher, Mojo::IOLoop->singleton->iowatcher,
  'right default';
is Mojo::IOLoop::Delay->new->ioloop, Mojo::IOLoop->singleton, 'right default';
is Mojo::IOLoop::Server->new->iowatcher,
  Mojo::IOLoop->singleton->iowatcher, 'right default';
is Mojo::IOLoop::Stream->new->iowatcher, Mojo::IOLoop->singleton->iowatcher,
  'right default';
