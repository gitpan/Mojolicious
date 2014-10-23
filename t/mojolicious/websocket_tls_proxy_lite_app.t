#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

use strict;
use warnings;

use Mojo::IOLoop;
use Test::More;

# Make sure sockets are working
plan skip_all => 'IO::Socket::SSL required for this test!'
  unless Mojo::IOLoop::TLS;
plan skip_all => 'working sockets required for this test!'
  unless my $proxy = Mojo::IOLoop->new->generate_port;
plan tests => 16;

# I was a hero to broken robots 'cause I was one of them, but how can I sing
# about being damaged if I'm not?
# That's like Christina Aguilera singing Spanish.
# Ooh, wait! That's it! I'll fake it!
use Mojo::Client;
use Mojo::Server::Daemon;
use Mojolicious::Lite;

# Silence
app->log->level('fatal');

# GET /
get '/' => sub { shift->render_text('Hello World!') };

# GET /proxy
get '/proxy' => sub {
    my $self = shift;
    $self->render_text($self->req->url);
};

# Websocket /test
websocket '/test' => sub {
    my $self = shift;
    my $flag = 0;
    $self->receive_message(
        sub {
            my ($self, $message) = @_;
            $self->send_message("${message}test2");
            $flag = 24;
        }
    );
};

# HTTP server for testing
my $client = Mojo::Client->new;
my $loop   = $client->ioloop;
my $server = Mojo::Server::Daemon->new(app => app, ioloop => $loop);
my $port   = Mojo::IOLoop->new->generate_port;
$server->listen("https://*:$port");
$server->prepare_ioloop;

# Connect proxy server for testing
my $c = {};
my $connected;
my ($read, $sent, $fail) = 0;
$loop->listen(
    port    => $proxy,
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
                $connected = "$1:$2";
                if ($2 == $port + 1) {
                    $fail = 1;
                    $2    = $port;
                }
                my $server = $loop->connect(
                    address    => $1,
                    port       => $2 || 80,
                    connect_cb => sub {
                        my ($loop, $server) = @_;
                        $c->{$client}->{connection} = $server;
                        $c->{$client}->{server} =
                          $fail
                          ? "HTTP/1.1 404 NOT FOUND\x0d\x0a"
                          . "Connection: close\x0d\x0a\x0d\x0a"
                          : "HTTP/1.1 200 OK\x0d\x0a"
                          . "Connection: keep-alive\x0d\x0a\x0d\x0a";
                        $loop->writing($client);
                    },
                    error_cb => sub {
                        shift->drop($client);
                        delete $c->{$client};
                    },
                    read_cb => sub {
                        my ($loop, $server, $chunk) = @_;
                        $read += length $chunk;
                        $c->{$client}->{server} ||= '';
                        $c->{$client}->{server} .= $chunk;
                        $loop->writing($client);
                    },
                    write_cb => sub {
                        my ($loop, $server) = @_;
                        $loop->not_writing($server);
                        my $chunk = delete $c->{$client}->{client} || '';
                        $sent += length $chunk;
                        return $chunk;
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
);

# GET / (normal request)
is($client->get("https://localhost:$port/")->success->body, 'Hello World!');

# WebSocket /test (normal websocket)
my $result;
$client->websocket(
    "wss://localhost:$port/test" => sub {
        my $self = shift;
        $self->receive_message(
            sub {
                my ($self, $message) = @_;
                $result = $message;
                $self->finish;
            }
        );
        $self->send_message('test1');
    }
)->process;
is($result, 'test1test2');

# GET http://kraih.com/proxy (proxy request)
$client->https_proxy("http://localhost:$proxy");
is($client->get("https://localhost:$port/")->success->body, 'Hello World!');

# GET http://kraih.com/proxy (kept alive proxy request)
$client->https_proxy("http://localhost:$proxy");
my $tx = $client->build_tx(GET => "https://localhost:$port/");
$client->process($tx);
is($tx->success->body, 'Hello World!');
is($tx->kept_alive,    1);

# WebSocket /test (kept alive proxy websocket)
$client->https_proxy("http://localhost:$proxy");
$result = undef;
my $kept_alive;
$client->websocket(
    "wss://localhost:$port/test" => sub {
        my $self = shift;
        $kept_alive = $self->tx->kept_alive;
        $self->receive_message(
            sub {
                my ($self, $message) = @_;
                $result = $message;
                $self->finish;
            }
        );
        $self->send_message('test1');
    }
)->process;
is($kept_alive, 1);
is($connected,  "localhost:$port");
is($result,     'test1test2');
ok($read > 25);
ok($sent > 25);

# WebSocket /test (proxy websocket)
$client->https_proxy("http://localhost:$proxy");
($connected, $result, $read, $sent) = undef;
$client->websocket(
    "wss://localhost:$port/test" => sub {
        my $self = shift;
        $self->receive_message(
            sub {
                my ($self, $message) = @_;
                $result = $message;
                $self->finish;
            }
        );
        $self->send_message('test1');
    }
)->process;
is($connected, "localhost:$port");
is($result,    'test1test2');
ok($read > 25);
ok($sent > 25);

# WebSocket /test (proxy websocket with bad target)
$client->https_proxy("http://localhost:$proxy");
my $port2 = $port + 1;
my ($success, $error);
$client->websocket(
    "wss://localhost:$port2/test" => sub {
        my ($self, $tx) = @_;
        $success = $tx->success;
        $error   = $tx->error;
    }
)->process;
is($success, undef);
is($error,   'Proxy connection failed.');
