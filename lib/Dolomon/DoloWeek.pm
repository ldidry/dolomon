package Dolomon::DoloWeek;
use Mojo::Base 'Dolomon::DoloCommon';

has 'table' => 'dolos_week';
has 'dolo_id';
has 'year';
has 'week';
has 'count';

sub increment_or_create {
    my $c = shift;

    if (defined $c->id) {
        $c->increment;
    } else {
        $c = $c->create({
            dolo_id => $c->dolo_id,
            year    => $c->year,
            week    => $c->week,
            count   => 1,
        });
    }

    return $c;
}

1;
