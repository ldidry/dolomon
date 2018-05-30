package Dolomon::Plugin::Helpers;
use Mojo::Base 'Mojolicious::Plugin';
use Data::Entropy qw(entropy_source);
use Mojo::Collection;
use Mojo::File;
use Mojo::Util qw(decode);
use ISO::639_1;

sub register {
    my ($self, $app) = @_;

    $app->plugin('PgURLHelper');

    $app->helper(pg                 => \&_pg);
    $app->helper(active             => \&_active);
    $app->helper(shortener          => \&_shortener);
    $app->helper(available_langs    => \&_available_langs);
    $app->helper(time_to_clean      => \&_time_to_clean);
    $app->helper(iso639_native_name => \&_iso639_native_name);

    $app->hook(
        before_dispatch => sub {
            my $c = shift;
            $c->languages($c->cookie('dolomon_lang')) if $c->cookie('dolomon_lang');
        }
    );
}

sub _pg {
    my $c     = shift;

    state $pg = Mojo::Pg->new($c->app->pg_url($c->app->config('db')));
}

sub _active {
    my $c = shift;
    my $r = shift;

    return ($c->current_route eq $r) ? ' class="active"' : '';
}

sub _shortener {
    my $c      = shift;
    my $length = shift;

    my @chars  = ('a'..'z','A'..'Z','0'..'9', '-', '_');
    my $result = '';
    foreach (1..$length) {
        $result .= $chars[entropy_source->get_int(scalar(@chars))];
    }
    return $result;
}

sub _available_langs {
    my $c      = shift;

    state $langs = Mojo::Collection->new(
        glob($c->app->home->rel_file('themes/'.$c->config('theme').'/lib/Dolomon/I18N/*po')),
        glob($c->app->home->rel_file('themes/default/lib/Dolomon/I18N/*po'))
    )->map(
        sub {
            Mojo::File->new($_)->basename('.po');
        }
    )->uniq->sort(
        sub {
            $c->l($a) cmp $c->l($b)
        }
    )->to_array;
}

sub _time_to_clean {
    my $c    = shift;
    my $time = time;

    state $last_cleaning;

    # If the last cleaning was less than 2 hours ago
    if (defined $last_cleaning && ($last_cleaning + 7200 > $time)) {
        return 0
    }

    $last_cleaning = $time;
    return 1;
}

sub _iso639_native_name {
    my $c = shift;
    return decode 'UTF-8', get_iso639_1(shift)->{nativeName};
}

1;
