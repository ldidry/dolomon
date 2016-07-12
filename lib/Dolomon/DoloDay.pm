package Dolomon::DoloDay;
use Mojo::Base 'Dolomon::DoloCommon';

has 'table' => 'dolos_day';
has 'dolo_id';
has 'year';
has 'month';
has 'week';
has 'day';
has 'count';

sub increment_or_create {
    my $c = shift;

    if (defined $c->id) {
        $c->increment;
    } else {
        $c = $c->create({
            dolo_id => $c->dolo_id,
            year    => $c->year,
            month   => $c->month,
            week    => $c->week,
            day     => $c->day,
            count   => 1
        });
    }

    return $c;
}

1;
