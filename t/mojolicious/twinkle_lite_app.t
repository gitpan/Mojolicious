use Mojo::Base -strict;

# Disable IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More tests => 29;

# "Pizza delivery for...
#  I. C. Weiner. Aww... I always thought by this stage in my life I'd be the
#  one making the crank calls."
use Mojolicious::Lite;
use Test::Mojo;

# Custom format
app->renderer->default_format('foo');

# Twinkle template syntax
my $twinkle = {
  auto_escape     => 0,
  capture_end     => '-',
  capture_start   => '+',
  escape_mark     => '*',
  expression_mark => '*',
  line_start      => '.',
  tag_end         => '**',
  tag_start       => '**',
  trim_mark       => '*'
};

# Plugins
plugin EPRenderer => {name => 'twinkle', template => $twinkle};
plugin PODRenderer => {no_perldoc => 1};
plugin PODRenderer =>
  {name => 'teapod', preprocess => 'twinkle', no_perldoc => 1};
my $config = plugin JSONConfig =>
  {default => {foo => 'bar'}, ext => 'conf', template => $twinkle};
is $config->{foo},  'bar', 'right value';
is $config->{test}, 23,    'right value';

# GET /
get '/' => {name => '<sebastian>'} => 'index';

# GET /advanced
get '/advanced' => 'advanced';

# GET /docs
get '/docs' => {codename => 'snowman'} => 'docs';

# GET /docs
get '/docs2' => {codename => 'snowman'} => 'docs2';

# GET /docs3
get '/docs3' => sub { shift->stash(codename => undef) } => 'docs';

# GET /rest
get '/rest' => sub {
  shift->respond_to(
    foo  => {text => 'foo works!'},
    html => {text => 'html works!'}
  );
};

# GET /dead
get '/dead' => sub {die};

my $t = Test::Mojo->new;

# GET /
$t->get_ok('/')->status_is(200)->content_like(qr/testHello <sebastian>!123/);

# GET /advanced
$t->get_ok('/advanced')->status_is(200)
  ->content_is("&lt;escape me&gt;\n123423");

# GET /docs
$t->get_ok('/docs')->status_is(200)->content_like(qr!<h3>snowman</h3>!);

# GET /docs2
$t->get_ok('/docs2')->status_is(200)->content_like(qr!<h2>snowman</h2>!);

# GET /docs3
$t->get_ok('/docs3')->status_is(200)->content_like(qr!<h3></h3>!);

# GET /rest (foo format)
$t->get_ok('/rest')->status_is(200)->content_is('foo works!');

# GET /rest.html (html format)
$t->get_ok('/rest.html')->status_is(200)->content_is('html works!');

# GET /perldoc (disabled)
$t->get_ok('/perldoc')->status_is(404)->content_is("foo not found!\n");

# GET /dead (exception template with custom format)
$t->get_ok('/dead')->status_is(500)->content_is("foo exception!\n");

__DATA__
@@ index.foo.twinkle
. layout 'twinkle';
Hello *** $name **!\

@@ layouts/twinkle.foo.ep
test<%= content %>123\

@@ advanced.foo.twinkle
.** '<escape me>'
. my $numbers = [1 .. 4];
 ** for my $i (@$numbers) { ***
 *** $i ***
 ** } ***
 ** my $foo = (+*** 23 **-)->();*** *** $foo ***

@@ docs.foo.pod
% no warnings;
<%= '=head3 ' . $codename %>

@@ docs2.foo.teapod
.** '=head2 ' . $codename

@@ exception.foo.ep
foo exception!

@@ not_found.foo.ep
foo not found!
