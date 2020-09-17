package Dolomon::Export;
use Mojo::Base 'Dolomon::Db';

has 'table' => 'data_exports';
has 'user_id';
has 'token';
has 'created_at';
has 'finished_at';
has 'expired';

sub clean_exports {
    my $c = shift;

    my $to_remove = $c->app->pg->db->query("SELECT id, token FROM data_exports WHERE expired = false AND finished_at < (CURRENT_TIMESTAMP - INTERVAL '7 DAYS')");
    $to_remove->hashes->each(sub {
        my ($e, $num) = @_;
        Mojo::File->new('exports', $e->{token}.'.json')->remove;
        $c->app->pg->db->query('UPDATE data_exports SET expired = true WHERE id = ?', $e->{id});
    });
}

1;
