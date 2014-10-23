use Mojo::Base -strict;

use Test::More;
use Mojolicious::Controller;

# Partial rendering
my $c = Mojolicious::Controller->new;
$c->app->log->level('fatal');
is $c->render_to_string(text => 'works'), 'works', 'renderer is working';

# Normal rendering with default format
my $renderer = $c->app->renderer->default_format('test');
$renderer->add_handler(
  debug => sub {
    my ($renderer, $c, $output) = @_;
    $$output .= 'Hello Mojo!';
  }
);
$c->stash->{template} = 'something';
$c->stash->{handler}  = 'debug';
is_deeply [$renderer->render($c)], ['Hello Mojo!', 'test'], 'normal rendering';

# Normal rendering with custom format
$c->stash->{format}   = 'something';
$c->stash->{template} = 'something';
$c->stash->{handler}  = 'debug';
is_deeply [$renderer->render($c)], ['Hello Mojo!', 'something'],
  'normal rendering';

# Normal rendering with layout
delete $c->stash->{format};
$c->stash->{template} = 'something';
$c->stash->{layout}   = 'something';
$c->stash->{handler}  = 'debug';
is_deeply [$renderer->render($c)], ['Hello Mojo!Hello Mojo!', 'test'],
  'normal rendering with layout';
is delete $c->stash->{layout}, 'something';

# Rendering a path with dots
$c->stash->{template} = 'some.path.with.dots/template';
$c->stash->{handler}  = 'debug';
is_deeply [$renderer->render($c)], ['Hello Mojo!', 'test'],
  'rendering a path with dots';

# Unrecognized handler
my $log = '';
my $cb = $c->app->log->on(message => sub { $log .= pop });
$c->stash->{handler} = 'not_defined';
is $renderer->render($c), undef, 'return undef for unrecognized handler';
like $log, qr/No handler for "not_defined" available\./, 'right message';
$c->app->log->unsubscribe(message => $cb);

# Default template name
$c->stash(controller => 'foo', action => 'bar');
is $c->app->renderer->template_for($c), 'foo/bar', 'right template name';

# Big cookie
$log = '';
$cb = $c->app->log->on(message => sub { $log .= pop });
$c->cookie(foo => 'x' x 4097);
like $log, qr/Cookie "foo" is bigger than 4096 bytes\./, 'right message';
$c->app->log->unsubscribe(message => $cb);

# Nested helpers
my $first = Mojolicious::Controller->new;
$first->app->log->level('fatal');
$first->app->helper('myapp.defaults' => sub { shift->app->defaults(@_) });
ok $first->app->renderer->get_helper('myapp'),          'found helper';
ok $first->app->renderer->get_helper('myapp.defaults'), 'found helper';
is $first->app->renderer->get_helper('myap.'),          undef, 'no helper';
is $first->app->renderer->get_helper('yapp'),           undef, 'no helper';
$first->myapp->defaults(foo => 'bar');
is $first->myapp->defaults('foo'), 'bar', 'right result';
is $first->app->myapp->defaults('foo'), 'bar', 'right result';
my $second = Mojolicious::Controller->new;
$second->app->log->level('fatal');
is $second->app->renderer->get_helper('myapp'),          undef, 'no helper';
is $second->app->renderer->get_helper('myapp.defaults'), undef, 'no helper';
$second->app->helper('myapp.defaults' => sub {'nothing'});
my $myapp = $first->myapp;
is $first->myapp->defaults('foo'),  'bar',     'right result';
is $second->myapp->defaults('foo'), 'nothing', 'right result';
is $first->myapp->defaults('foo'),  'bar',     'right result';

# Missing method (AUTOLOAD)
my $class = ref $first->myapp;
eval { $first->myapp->missing };
like $@, qr/^Can't locate object method "missing" via package "$class"/,
  'right error';
eval { $first->app->myapp->missing };
like $@, qr/^Can't locate object method "missing" via package "$class"/,
  'right error';

done_testing();
