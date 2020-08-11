package Dolomon::Validation;
use Mojo::Base 'Mojolicious::Validator::Validation';

sub check {
    my ($self, $check) = (shift, shift);

    return $self unless $self->is_valid;

    my $cb     = $self->validator->checks->{$check};
    my $name   = $self->topic;
    my $values = $self->output->{$name};
    for my $value (ref $values eq 'ARRAY' ? @$values : $values) {
        next unless my $result = $self->$cb($name, $value, @_);
        $self->{error}{$name} = {} unless defined $self->{error}{$name};
        return $self->{error}{$name}->{$check} = [$result, @_]);
    }

    return $self;
}

sub csrf_protect {
    my $self  = shift;
    my $token = $self->input->{csrf_token};
    $self->error(csrf_token => { csrf_protect => [] }) unless $token && $token eq ($self->csrf_token // '');
    return $self;
}


sub required {
    my ($self, $name) = (shift, shift);
    return $self if $self->optional($name, @_)->is_valid;
    return $self->error($name => {required => [] });
}

1;
