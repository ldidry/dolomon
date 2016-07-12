package Dolomon::Tag;
use Mojo::Base 'Dolomon::Db';

has 'table' => 'tags';
has 'name';
has 'user_id';
has 'dolos' => sub {
    return Mojo::Collection->new();
};

sub new {
    my $c = shift;

    $c = $c->SUPER::new(@_);

    my @dolos = ();
    if (defined $c->id) {
        my $r = $c->app->pg->db->query('SELECT d.id, d.url, d.short, d.name, d.extra, d.count, d.initial_count, d.category_id, c.name AS category_name, d.parent_id, d.created_at FROM dolos d JOIN dolo_has_tags t ON t.dolo_id = d.id JOIN categories c ON c.id = d.category_id WHERE t.tag_id = ? AND d.parent_id IS NULL ORDER BY id', $c->id);
        while (my $next = $r->hash) {
            my $dolo = Dolomon::Dolo->new(app => $c->app)
                ->category_id($next->{category_id})
                ->category_name($next->{category_name})
                ->id($next->{id})
                ->url($next->{url})
                ->short($next->{short})
                ->name($next->{name})
                ->extra($next->{extra})
                ->count($next->{count})
                ->created_at($next->{created_at});
            my @achild = ();
            my $children = $c->app->pg->db->query('SELECT d.id, d.url, d.short, d.name, d.extra, d.count, d.initial_count, d.category_id, c.name AS category_name, d.parent_id, d.created_at FROM dolos d JOIN categories c ON c.id = d.category_id WHERE parent_id = ? ORDER BY id', $next->{id})->hashes;
            $children->each(sub {
                my ($e, $num) = @_;
                my $child = Dolomon::Dolo->new(app => $c->app)
                    ->category_id($e->{category_id})
                    ->category_name($e->{category_name})
                    ->id($e->{id})
                    ->url($e->{url})
                    ->short($e->{short})
                    ->name($e->{name})
                    ->extra($e->{extra})
                    ->parent_id($e->{parent_id})
                    ->count($e->{count})
                    ->created_at($e->{created_at});

                my $tags = $c->app->pg->db->query('SELECT t.id, t.name FROM dolo_has_tags d JOIN tags t ON t.id = d.tag_id WHERE d.dolo_id = ? ORDER BY t.name', $e->{id})->hashes;
                my @atags;
                $tags->each(sub {
                    my ($t, $num) = @_;
                    push @atags, $t;
                });
                $child->tags(\@atags);
                push @achild, $child;
            });
            $dolo->children(Mojo::Collection->new(@achild));

            my @atags;
            my $tags = $c->app->pg->db->query('SELECT t.id, t.name FROM dolo_has_tags d JOIN tags t ON t.id = d.tag_id WHERE d.dolo_id = ? ORDER BY t.name', $next->{id})->hashes;
            $tags->each(sub {
                my ($e, $num) = @_;
                push @atags, $e;
            });
            $dolo->tags(\@atags);
            push @dolos, $dolo;
        }
    }

    $c->dolos(Mojo::Collection->new(@dolos));

    return $c;
}

sub bind_to {
    my $c       = shift;
    my $dolo_id = shift;

    $c->app->pg->db->query('INSERT INTO dolo_has_tags (tag_id, dolo_id) VALUES (?, ?)', ($c->id, $dolo_id));
}

sub unbind_from {
    my $c       = shift;
    my $dolo_id = shift;

    $c->app->pg->db->query('DELETE FROM dolo_has_tags WHERE tag_id = ? AND dolo_id = ?', ($c->id, $dolo_id));
}

sub count {
    my $c = shift;

    return $c->app->pg->db->query('SELECT sum(d.count) FROM dolos d JOIN dolo_has_tags t ON t.dolo_id = d.id WHERE t.tag_id = ?', $c->id)->array->[0];
}

sub get_raw_dys {
    my $c = shift;

    return $c->app->pg->db->query('SELECT y.* from dolos_year y JOIN dolos d ON y.dolo_id = d.id JOIN dolo_has_tags t ON t.dolo_id = d.id WHERE t.tag_id = ? ORDER BY year ASC', $c->id)->hashes;
}

sub get_raw_dms {
    my $c = shift;

    return $c->app->pg->db->query('SELECT m.* from dolos_month m JOIN dolos d ON m.dolo_id = d.id JOIN dolo_has_tags t ON t.dolo_id = d.id WHERE t.tag_id = ? ORDER BY year, month ASC', $c->id)->hashes;
}

sub get_raw_dws {
    my $c = shift;

    return $c->app->pg->db->query('SELECT w.* from dolos_week w JOIN dolos d ON w.dolo_id = d.id JOIN dolo_has_tags t ON t.dolo_id = d.id WHERE t.tag_id = ? ORDER BY year, week ASC', $c->id)->hashes;
}

sub get_raw_dds {
    my $c = shift;

    return $c->app->pg->db->query('SELECT a.* from dolos_day a JOIN dolos d ON a.dolo_id = d.id JOIN dolo_has_tags t ON t.dolo_id = d.id WHERE t.tag_id = ? ORDER BY year, month, day ASC', $c->id)->hashes;
}

sub get_raw_dhs {
    my $c = shift;

    return $c->app->pg->db->query('SELECT h.* from dolos_hits h JOIN dolos d ON h.dolo_id = d.id JOIN dolo_has_tags t ON t.dolo_id = d.id WHERE t.tag_id = ? ORDER BY ts ASC', $c->id)->hashes;
}
1;
