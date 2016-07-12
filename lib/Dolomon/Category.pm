package Dolomon::Category;
use Mojo::Base 'Dolomon::Db';
use Dolomon::Dolo;

has 'table' => 'categories';
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
        my $r = $c->app->pg->db->query('SELECT id, url, short, name, extra, count, initial_count, category_id, parent_id, created_at FROM dolos WHERE category_id = ? AND parent_id IS NULL ORDER BY id', $c->id);
        while (my $next = $r->hash) {
            my $dolo = Dolomon::Dolo->new(app => $c->app)
                ->category_id($c->id)
                ->category_name($c->name)
                ->id($next->{id})
                ->url($next->{url})
                ->short($next->{short})
                ->name($next->{name})
                ->extra($next->{extra})
                ->count($next->{count})
                ->created_at($next->{created_at});
            my @achild = ();
            my $children = $c->app->pg->db->query('SELECT id, url, short, name, extra, count, initial_count, category_id, parent_id, created_at FROM dolos WHERE parent_id = ? ORDER BY id', $next->{id})->hashes;
            $children->each(sub {
                my ($e, $num) = @_;
                my $child = Dolomon::Dolo->new(app => $c->app)
                    ->category_id($c->id)
                    ->category_name($c->name)
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

sub evacuate_to {
    my $c          = shift;
    my $new_cat_id = shift;
    $c->app->pg->db->query('UPDATE dolos SET category_id = ? WHERE category_id = ?', ($new_cat_id, $c->id));
}

sub count {
    my $c = shift;

    return $c->app->pg->db->query('SELECT sum(count) FROM dolos WHERE category_id = ?', $c->id)->array->[0];
}

sub get_raw_dys {
    my $c = shift;

    return $c->app->pg->db->query('SELECT y.* FROM dolos_year y JOIN dolos d ON y.dolo_id = d.id WHERE d.category_id = ? ORDER BY year ASC', $c->id)->hashes;
}

sub get_raw_dms {
    my $c = shift;

    return $c->app->pg->db->query('SELECT m.* FROM dolos_month m JOIN dolos d ON m.dolo_id = d.id WHERE d.category_id = ? ORDER BY year, month ASC', $c->id)->hashes;
}

sub get_raw_dws {
    my $c = shift;

    return $c->app->pg->db->query('SELECT w.* FROM dolos_week w JOIN dolos d ON w.dolo_id = d.id WHERE d.category_id = ? ORDER BY year, week ASC', $c->id)->hashes;
}

sub get_raw_dds {
    my $c = shift;

    return $c->app->pg->db->query('SELECT a.* FROM dolos_day a JOIN dolos d ON a.dolo_id = d.id WHERE d.category_id = ? ORDER BY year, month, day ASC', $c->id)->hashes;
}

sub get_raw_dhs {
    my $c = shift;

    return $c->app->pg->db->query('SELECT h.* FROM dolos_hits h JOIN dolos d ON h.dolo_id = d.id WHERE d.category_id = ? ORDER BY ts ASC', $c->id)->hashes;
}

1;
