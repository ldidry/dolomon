package Dolomon::DoloYear;
use Mojo::Base 'Dolomon::DoloCommon';

has 'table' => 'dolos_year';
has 'dolo_id';
has 'year';
has 'count';

sub increment_or_create {
    my $c = shift;

    if (defined $c->id) {
        $c->increment;
    } else {
        $c = $c->create({
            dolo_id => $c->dolo_id,
            year    => $c->year,
            count   => 1,
        });
    }

    return $c;
}

1;
