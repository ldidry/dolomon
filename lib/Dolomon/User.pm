package Dolomon::User;
use Mojo::Base 'Dolomon::DoloCommon';
use Mojo::Collection;
use Dolomon::Dolo;
use Dolomon::Category;
use Dolomon::Tag;
use Dolomon::Application;

has 'table' => 'users';
has 'login';
has 'first_name';
has 'last_name';
has 'mail';
has 'password';
has 'last_login';
has 'count';
has 'confirmed';
has 'token';

sub update {
    my $c = shift;
    my $i = shift;
    my $x = shift;

    if (defined($x) && $x eq 'login') {
        my ($fields, $params) = $c->map_fields_for_update($i);
        push @{$fields}, 'last_login = NOW()';
        push @{$params}, $c->id;

        my $q = join(', ', @{$fields});

        my $r = $c->app->pg->db->query('UPDATE '.$c->table.' SET '.$q.' WHERE id = ? RETURNING *;', @{$params});

        if ($r->rows == 1) {
            $c->map_fields_to_attr($r->hash);
        }
    } else {
        $c = $c->SUPER::update(($i));
    }
    return $c;
}

sub delete_cascade {
    my $c = shift;

    $c->app->pg->db->query('DELETE FROM dolos d WHERE d.category_id IN (SELECT c.id FROM categories c WHERE c.user_id = ?)', $c->id);

    return $c->delete();
}

sub renew_token {
    my $c = shift;

    my $r = $c->app->pg->db->query('UPDATE '.$c->table.' SET token = uuid_generate_v4() WHERE id = ? RETURNING token;', $c->id);

    if ($r->rows == 1) {
        $c->token($r->hash->{token});
    }

    return $c;
}

sub get_dolos {
    my $c = shift;

    my $r = $c->app->pg->db->query('SELECT d.id FROM dolos d JOIN categories c ON d.category_id = c.id WHERE c.user_id = ? ORDER BY d.id', $c->id);
    my @dolos = ();
    while (my $next = $r->hash) {
        push @dolos, Dolomon::Dolo->new(app => $c->app, id => $next->{id});
    }

    return Mojo::Collection->new(@dolos);
}

sub get_categories {
    my $c = shift;

    my $r = $c->app->pg->db->query('SELECT id FROM categories WHERE user_id = ? ORDER BY id', $c->id);
    my @cats = ();
    while (my $next = $r->hash) {
        push @cats, Dolomon::Category->new(app => $c->app, id => $next->{id});
    }

    return Mojo::Collection->new(@cats);
}

sub get_tags {
    my $c = shift;

    my $r = $c->app->pg->db->query('SELECT id FROM tags WHERE user_id = ? ORDER BY id', $c->id);
    my @tags = ();
    while (my $next = $r->hash) {
        push @tags, Dolomon::Tag->new(app => $c->app, id => $next->{id});
    }

    return Mojo::Collection->new(@tags);
}

sub get_applications {
    my $c = shift;

    my $r = $c->app->pg->db->query('SELECT id FROM applications WHERE user_id = ? ORDER BY id', $c->id);
    my @apps = ();
    while (my $next = $r->hash) {
        push @apps, Dolomon::Application->new(app => $c->app, id => $next->{id});
    }

    return Mojo::Collection->new(@apps);
}

sub get_exports {
    my $c = shift;

    my $r = $c->app->pg->db->query('SELECT id FROM data_exports WHERE user_id = ? ORDER BY id', $c->id);
    my @exports = ();
    while (my $next = $r->hash) {
        push @exports, Dolomon::Export->new(app => $c->app, id => $next->{id});
    }

    return Mojo::Collection->new(@exports);
}

sub get_stats {
    my $c = shift;

    return {
        cats  => $c->get_cat_nb,
        tags  => $c->get_tag_nb,
        apps  => $c->get_app_nb,
        dolos => $c->get_dolo_nb,
        total => $c->count,
    }
}

sub get_cat_nb {
    my $c = shift;
    return $c->app->pg->db->query('SELECT count(id) FROM categories WHERE user_id = ?', $c->id)->array->[0];
}

sub get_tag_nb {
    my $c = shift;
    return $c->app->pg->db->query('SELECT count(id) FROM tags WHERE user_id = ?', $c->id)->array->[0];
}

sub get_app_nb {
    my $c = shift;
    return $c->app->pg->db->query('SELECT count(id) FROM applications WHERE user_id = ?', $c->id)->array->[0];
}

sub get_dolo_nb {
    my $c = shift;
    return $c->app->pg->db->query('SELECT count(d.id) FROM dolos d JOIN categories c ON d.category_id = c.id WHERE c.user_id = ?', $c->id)->array->[0];
}

sub export_data {
    my $c = shift;

    my $categories    = $c->app->pg->db->query(
        'SELECT * FROM categories   WHERE user_id = ? ORDER BY id', $c->id
    )->hashes->to_array;
    my $tags          = $c->app->pg->db->query(
        'SELECT * FROM tags         WHERE user_id = ? ORDER BY id', $c->id
    )->hashes->to_array;
    my $applications  = $c->app->pg->db->query(
        'SELECT * FROM applications WHERE user_id = ? ORDER BY id', $c->id
    )->hashes->to_array;
    my $dolos         = $c->app->pg->db->query(
        'SELECT d.* FROM dolos d                                        JOIN categories c ON d.category_id = c.id WHERE c.user_id = ? ORDER BY d.id', $c->id
    )->hashes->to_array;
    my $dolos_year    = $c->app->pg->db->query(
        'SELECT y.* FROM dolos_year    y JOIN dolos d ON y.dolo_id = d.id JOIN categories c ON d.category_id = c.id WHERE c.user_id = ? ORDER BY y.id', $c->id
    )->hashes->to_array;
    my $dolos_week    = $c->app->pg->db->query(
        'SELECT y.* FROM dolos_week    y JOIN dolos d ON y.dolo_id = d.id JOIN categories c ON d.category_id = c.id WHERE c.user_id = ? ORDER BY y.id', $c->id
    )->hashes->to_array;
    my $dolos_month   = $c->app->pg->db->query(
        'SELECT y.* FROM dolos_month   y JOIN dolos d ON y.dolo_id = d.id JOIN categories c ON d.category_id = c.id WHERE c.user_id = ? ORDER BY y.id', $c->id
    )->hashes->to_array;
    my $dolos_day     = $c->app->pg->db->query(
        'SELECT y.* FROM dolos_day     y JOIN dolos d ON y.dolo_id = d.id JOIN categories c ON d.category_id = c.id WHERE c.user_id = ? ORDER BY y.id', $c->id
    )->hashes->to_array;
    my $dolos_hits    = $c->app->pg->db->query(
        'SELECT y.* FROM dolos_hits    y JOIN dolos d ON y.dolo_id = d.id JOIN categories c ON d.category_id = c.id WHERE c.user_id = ? ORDER BY y.id', $c->id
    )->hashes->to_array;
    my $dolo_has_tags = $c->app->pg->db->query(
        'SELECT d.* FROM dolo_has_tags d JOIN tags t  ON d.tag_id = t.id                                            WHERE t.user_id = ? ORDER BY d.dolo_id', $c->id
    )->hashes->to_array;
    my $user_count  = $c->app->pg->db->select($c->table, ['count'], { id => $c->id })->hash->{count};
    return {
        categories    => $categories, 
        tags          => $tags,
        applications  => $applications,
        dolos         => $dolos,
        dolos_year    => $dolos_year,
        dolos_week    => $dolos_week,
        dolos_month   => $dolos_month,
        dolos_day     => $dolos_day,
        dolos_hits    => $dolos_hits,
        dolo_has_tags => $dolo_has_tags,
        user_count    => $user_count
    };
}

1;
