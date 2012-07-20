use Mojo::Base -strict;

# Disable IPv6, TLS and libev
BEGIN {
  $ENV{MOJO_NO_IPV6} = $ENV{MOJO_NO_TLS} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More tests => 92;

# "The strong must protect the sweet."
use Mojo::IOLoop;
use Mojo::UserAgent;
use Mojolicious::Lite;

# Silence
app->log->level('fatal');

# GET /
get '/' => {text => 'works!'};

# GET /timeout
my $timeout = undef;
get '/timeout' => sub {
  my $self = shift;
  Mojo::IOLoop->stream($self->tx->connection)
    ->timeout($self->param('timeout'));
  $self->on(finish => sub { $timeout = 1 });
  $self->render_later;
};

# GET /no_length
get '/no_length' => sub {
  my $self = shift;
  $self->finish('works too!');
  $self->rendered(200);
};

# GET /echo
get '/echo' => sub {
  my $self = shift;
  $self->render_data($self->req->body);
};

# POST /echo
post '/echo' => sub {
  my $self = shift;
  $self->render_data($self->req->body);
};

# Proxy detection
{
  my $ua = Mojo::UserAgent->new;
  local $ENV{HTTP_PROXY}  = 'http://127.0.0.1';
  local $ENV{HTTPS_PROXY} = 'http://127.0.0.1:8080';
  local $ENV{NO_PROXY}    = 'mojolicio.us';
  $ua->detect_proxy;
  is $ua->http_proxy,  'http://127.0.0.1',      'right proxy';
  is $ua->https_proxy, 'http://127.0.0.1:8080', 'right proxy';
  $ua->http_proxy(undef);
  $ua->https_proxy(undef);
  is $ua->http_proxy,  undef, 'right proxy';
  is $ua->https_proxy, undef, 'right proxy';
  ok !$ua->need_proxy('dummy.mojolicio.us'), 'no proxy needed';
  ok $ua->need_proxy('icio.us'),   'proxy needed';
  ok $ua->need_proxy('localhost'), 'proxy needed';
  $ENV{HTTP_PROXY} = $ENV{HTTPS_PROXY} = $ENV{NO_PROXY} = undef;
  local $ENV{http_proxy}  = 'proxy.kraih.com';
  local $ENV{https_proxy} = 'tunnel.kraih.com';
  local $ENV{no_proxy}    = 'localhost,localdomain,foo.com,kraih.com';
  $ua->detect_proxy;
  is $ua->http_proxy,  'proxy.kraih.com',  'right proxy';
  is $ua->https_proxy, 'tunnel.kraih.com', 'right proxy';
  ok $ua->need_proxy('dummy.mojolicio.us'), 'proxy needed';
  ok $ua->need_proxy('icio.us'),            'proxy needed';
  ok !$ua->need_proxy('localhost'),             'proxy needed';
  ok !$ua->need_proxy('localhost.localdomain'), 'no proxy needed';
  ok !$ua->need_proxy('foo.com'),               'no proxy needed';
  ok !$ua->need_proxy('kraih.com'),             'no proxy needed';
  ok !$ua->need_proxy('www.kraih.com'),         'no proxy needed';
  ok $ua->need_proxy('www.kraih.com.com'), 'proxy needed';
}

# Max redirects
{
  local $ENV{MOJO_MAX_REDIRECTS} = 25;
  is(Mojo::UserAgent->new->max_redirects, 25, 'right value');
  $ENV{MOJO_MAX_REDIRECTS} = 0;
  is(Mojo::UserAgent->new->max_redirects, 0, 'right value');
}

# Timeouts
{
  is(Mojo::UserAgent->new->connect_timeout, 10, 'right value');
  local $ENV{MOJO_CONNECT_TIMEOUT} = 25;
  is(Mojo::UserAgent->new->connect_timeout,    25, 'right value');
  is(Mojo::UserAgent->new->inactivity_timeout, 20, 'right value');
  local $ENV{MOJO_INACTIVITY_TIMEOUT} = 25;
  is(Mojo::UserAgent->new->inactivity_timeout, 25, 'right value');
  $ENV{MOJO_INACTIVITY_TIMEOUT} = 0;
  is(Mojo::UserAgent->new->inactivity_timeout, 0, 'right value');
  is(Mojo::UserAgent->new->request_timeout,    0, 'right value');
  local $ENV{MOJO_REQUEST_TIMEOUT} = 25;
  is(Mojo::UserAgent->new->request_timeout, 25, 'right value');
  $ENV{MOJO_REQUEST_TIMEOUT} = 0;
  is(Mojo::UserAgent->new->request_timeout, 0, 'right value');
}

# GET / (non-blocking)
my $ua = Mojo::UserAgent->new(ioloop => Mojo::IOLoop->singleton);
my ($success, $code, $body);
$ua->get(
  '/' => sub {
    my $tx = pop;
    $success = $tx->success;
    $code    = $tx->res->code;
    $body    = $tx->res->body;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
ok $success, 'successful';
is $code,    200, 'right status';
is $body,    'works!', 'right content';

# Error in callback is logged
my $message = app->log->subscribers('message')->[0];
app->log->unsubscribe(message => $message);
app->log->level('error');
app->ua->once(error => sub { Mojo::IOLoop->stop });
ok app->ua->has_subscribers('error'), 'has subscribers';
my $err;
app->log->once(message => sub { $err .= pop });
app->ua->get('/' => sub { die 'error event works' });
Mojo::IOLoop->start;
app->log->level('fatal');
app->log->on(message => $message);
like $err, qr/error event works/, 'right error';

# GET / (HTTPS request without TLS support)
my $tx = $ua->get($ua->app_url->scheme('https'));
ok $tx->error, 'has error';

# GET / (blocking)
$tx = $ua->get('/');
ok $tx->success, 'successful';
ok !$tx->kept_alive, 'kept connection not alive';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# GET / (again)
$tx = $ua->get('/');
ok $tx->success,    'successful';
ok $tx->kept_alive, 'kept connection alive';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# GET /
$tx = $ua->get('/');
ok $tx->success, 'successful';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# GET / (callbacks)
my $finished;
$tx = $ua->build_tx(GET => '/');
$ua->once(
  start => sub {
    my ($self, $tx) = @_;
    $tx->on(finish => sub { $finished++ });
  }
);
$tx = $ua->start($tx);
ok $tx->success, 'successful';
is $finished, 1, 'finish event has been emitted';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# GET /no_length (missing Content-Length header)
$tx = $ua->get('/no_length');
ok $tx->success, 'successful';
ok !$tx->error, 'no error';
ok $tx->kept_alive, 'kept connection alive';
ok !$tx->keep_alive, 'keep connection not alive';
is $tx->res->code, 200,          'right status';
is $tx->res->body, 'works too!', 'right content';

# GET / (built-in web server)
$tx = $ua->get('/');
ok $tx->success, 'successful';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# POST /echo (non-blocking form)
($success, $code, $body) = undef;
$ua->post_form(
  '/echo' => {hello => 'world'} => sub {
    my ($self, $tx) = @_;
    $success = $tx->success;
    $code    = $tx->res->code;
    $body    = $tx->res->body;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
ok $success, 'successful';
is $code,    200, 'right status';
is $body,    'hello=world', 'right content';

# POST /echo (non-blocking JSON)
($success, $code, $body) = undef;
$ua->post_json(
  '/echo' => {hello => 'world'} => sub {
    my ($self, $tx) = @_;
    $success = $tx->success;
    $code    = $tx->res->code;
    $body    = $tx->res->body;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
ok $success, 'successful';
is $code,    200, 'right status';
is $body,    '{"hello":"world"}', 'right content';

# GET /timeout (built-in web server times out)
my $log = '';
$message = app->log->subscribers('message')->[0];
app->log->unsubscribe(message => $message);
app->log->level('debug');
app->log->on(message => sub { $log .= pop });
$tx = $ua->get('/timeout?timeout=0.5');
app->log->level('fatal');
app->log->on(message => $message);
ok !$tx->success, 'not successful';
is $tx->error, 'Premature connection close', 'right error';
is $timeout, 1, 'finish event has been emitted';
like $log, qr/Inactivity timeout\./, 'right log message';

# GET /timeout (client times out)
$ua->once(
  start => sub {
    my ($ua, $tx) = @_;
    $tx->on(
      connection => sub {
        my ($tx, $connection) = @_;
        Mojo::IOLoop->stream($connection)->timeout(0.5);
      }
    );
  }
);
$tx = $ua->get('/timeout?timeout=5');
ok !$tx->success, 'not successful';
is $tx->error, 'Inactivity timeout', 'right error';

# GET / (introspect)
my $req = my $res = '';
my $start = $ua->on(
  start => sub {
    my ($ua, $tx) = @_;
    $tx->on(
      connection => sub {
        my ($tx, $connection) = @_;
        my $stream = Mojo::IOLoop->stream($connection);
        my $read   = $stream->on(
          read => sub {
            my ($stream, $chunk) = @_;
            $res .= $chunk;
          }
        );
        my $write = $stream->on(
          write => sub {
            my ($stream, $chunk) = @_;
            $req .= $chunk;
          }
        );
        $tx->on(
          finish => sub {
            $stream->unsubscribe(read  => $read);
            $stream->unsubscribe(write => $write);
          }
        );
      }
    );
  }
);
$tx = $ua->get('/', 'whatever');
ok $tx->success, 'successful';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';
is scalar @{Mojo::IOLoop->stream($tx->connection)->subscribers('write')}, 0,
  'unsubscribed successfully';
is scalar @{Mojo::IOLoop->stream($tx->connection)->subscribers('read')}, 1,
  'unsubscribed successfully';
like $req, qr!^GET / .*whatever$!s,      'right request';
like $res, qr|^HTTP/.*200 OK.*works!$|s, 'right response';
$ua->unsubscribe(start => $start);
ok !$ua->has_subscribers('start'), 'unsubscribed successfully';

# GET /echo (stream with drain callback)
my $stream = 0;
$tx = $ua->build_tx(GET => '/echo');
my $i = 0;
my $drain;
$drain = sub {
  my $req = shift;
  return $ua->ioloop->timer(
    0.5 => sub {
      $req->write_chunk('');
      $tx->resume;
      $stream
        += @{Mojo::IOLoop->stream($tx->connection)->subscribers('drain')};
    }
  ) if $i >= 10;
  $req->write_chunk($i++, $drain);
  $tx->resume;
  return unless my $id = $tx->connection;
  $stream += @{Mojo::IOLoop->stream($id)->subscribers('drain')};
};
$tx->req->$drain;
$ua->start($tx);
ok $tx->success, 'successful';
ok !$tx->error, 'no error';
ok $tx->kept_alive, 'kept connection alive';
ok $tx->keep_alive, 'keep connection alive';
is $tx->res->code, 200,          'right status';
is $tx->res->body, '0123456789', 'right content';
is $stream, 1, 'no leaking subscribers';

# GET / (nested non-blocking requests after blocking one, with custom URL)
my @kept_alive;
$ua->get(
  $ua->app_url => sub {
    my ($self, $tx) = @_;
    push @kept_alive, $tx->kept_alive;
    $self->get(
      '/' => sub {
        my ($self, $tx) = @_;
        push @kept_alive, $tx->kept_alive;
        $self->get(
          $ua->app_url => sub {
            my ($self, $tx) = @_;
            push @kept_alive, $tx->kept_alive;
            Mojo::IOLoop->stop;
          }
        );
      }
    );
  }
);
Mojo::IOLoop->start;
is_deeply \@kept_alive, [undef, 1, 1], 'connections kept alive';

# GET / (simple nested non-blocking requests with timers)
@kept_alive = ();
$ua->get(
  '/' => sub {
    push @kept_alive, pop->kept_alive;
    Mojo::IOLoop->timer(
      0.25 => sub {
        $ua->get(
          '/' => sub {
            push @kept_alive, pop->kept_alive;
            Mojo::IOLoop->timer(0.25 => sub { Mojo::IOLoop->stop });
          }
        );
      }
    );
  }
);
Mojo::IOLoop->start;
is_deeply \@kept_alive, [1, 1], 'connections kept alive';

# GET / (blocking request after non-blocking one, with custom URL)
$tx = $ua->get($ua->app_url);
ok $tx->success, 'successful';
ok !$tx->kept_alive, 'kept connection not alive';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# Premature connection close
my $port = Mojo::IOLoop->generate_port;
my $id   = Mojo::IOLoop->server(
  address => '127.0.0.1',
  port    => $port,
  sub { Mojo::IOLoop->remove(pop) }
);
$tx = $ua->get("http://localhost:$port/");
ok !$tx->success, 'not successful';
is $tx->error, 'Premature connection close', 'right error';
