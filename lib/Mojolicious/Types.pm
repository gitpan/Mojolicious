package Mojolicious::Types;
use Mojo::Base -base;

# "Once again, the conservative, sandwich-heavy portfolio pays off for the
#  hungry investor."
has types => sub {
  {
    atom => 'application/atom+xml',
    bin  => 'application/octet-stream',
    css  => 'text/css',
    gif  => 'image/gif',
    gz   => 'application/x-gzip',
    htm  => 'text/html',
    html => 'text/html;charset=UTF-8',
    ico  => 'image/x-icon',
    jpeg => 'image/jpeg',
    jpg  => 'image/jpeg',
    js   => 'application/javascript',
    json => 'application/json',
    mp3  => 'audio/mpeg',
    mp4  => 'video/mp4',
    ogg  => 'audio/ogg',
    ogv  => 'video/ogg',
    pdf  => 'application/pdf',
    png  => 'image/png',
    rss  => 'application/rss+xml',
    svg  => 'image/svg+xml',
    txt  => 'text/plain',
    webm => 'video/webm',
    woff => 'application/font-woff',
    xml  => ['application/xml', 'text/xml'],
    zip  => 'application/zip'
  };
};

# "Magic. Got it."
sub detect {
  my ($self, $accept) = @_;

  # Detect extensions from MIME type
  return [] unless (($accept || '') =~ /^([^,]+?)(?:\;[^,]*)*$/);
  my $type = lc $1;
  my @exts;
  my $types = $self->types;
  for my $ext (sort keys %$types) {
    my @types = ref $types->{$ext} ? @{$types->{$ext}} : ($types->{$ext});
    $type eq $_ and push @exts, $ext for map { s/\;.*$//; lc $_ } @types;
  }

  return \@exts;
}

sub type {
  my ($self, $ext) = (shift, shift);
  my $types = $self->types;
  return ref $types->{$ext} ? $types->{$ext}[0] : $types->{$ext} unless @_;
  $types->{$ext} = shift;
  return $self;
}

1;

=head1 NAME

Mojolicious::Types - MIME types

=head1 SYNOPSIS

  use Mojolicious::Types;

  my $types = Mojolicious::Types->new;
  $types->type(foo => 'text/foo');
  say $types->type('foo');

=head1 DESCRIPTION

L<Mojolicious::Types> manages MIME types for L<Mojolicious>.

=head1 ATTRIBUTES

L<Mojolicious::Types> implements the following attributes.

=head2 C<types>

  my $map = $types->types;
  $types  = $types->types({png => 'image/png'});

List of MIME types.

=head1 METHODS

L<Mojolicious::Types> inherits all methods from L<Mojo::Base> and implements
the following ones.

=head2 C<detect>

  my $exts = $types->detect('application/json;q=9');

Detect file extensions from C<Accept> header value. Unspecific values that
contain more than one MIME type are currently ignored, since browsers often
don't really know what they actually want.

  # List detected extensions
  say for @{$types->detect('application/json')};

=head2 C<type>

  my $type = $types->type('png');
  $types   = $types->type(png => 'image/png');
  $types   = $types->type(json => [qw(application/json text/x-json)]);

Get or set MIME types for file extension, alternatives are only used for
detection.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
