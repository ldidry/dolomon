package Dolomon::DoloCommon;
use Mojo::Base 'Dolomon::Db';

sub increment {
    my $c   = shift;
    my $inc = shift;
       $inc = 1 unless defined $inc;

    my $h = $c->app->pg->db->query('UPDATE '.$c->table.' SET count = count + '.$inc.' WHERE id = ? RETURNING count', $c->id)->hashes;

    if ($h->size) {
        $c->count($h->first->{count});
        return $c;
    } else {
        return undef;
    }
}

1;
