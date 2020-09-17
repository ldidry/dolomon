# vim:set sw=4 ts=4 sts=4 ft=perl expandtab:
use Mojo::Base -strict, -signatures;
use Mojo::JSON qw(true false);
use Mojolicious;
use DateTime;
use DateTime::Format::Pg;
use Dolomon::Admin;
use Dolomon::Category;

use Test::More;
use Test::Mojo;

use FindBin qw($Bin);

$| = 1;

my $cfile;

BEGIN {
    use lib 'lib';
    $cfile = Mojo::File->new($Bin, '..', 'dolomon.conf');
    if (defined $ENV{MOJO_CONFIG}) {
        $cfile = Mojo::File->new($ENV{MOJO_CONFIG});
        unless (-e $cfile->to_abs) {
            $cfile = Mojo::File->new($Bin, '..', $ENV{MOJO_CONFIG});
        }
    }
} ## end BEGIN

my $t = Test::Mojo->new('Dolomon');

### Dolomon::Admin
##
# get_nb_users
$t->test('is', Dolomon::Admin->new(app => $t->app)->get_nb_users, 3, 'Dolomon::Admin->get_nb_users');

### Dolomon::Category
##
# evacuate_to
my $cat1 = Dolomon::Category->new(app => $t->app, id => 1);
my $cat3 = Dolomon::Category->new(app => $t->app, id => 3);
$t->test('is', $cat1->count, 15, 'Dolomon::Category->count on cat1');
$t->test('is', $cat3->count, undef, 'Dolomon::Category->count on cat3');
$t->app->dumper($cat1->evacuate_to(3));
$t->test('is', $cat1->count, undef, 'Dolomon::Category->count on cat1 after evacuation');
$t->test('is', $cat3->count, 15, 'Dolomon::Category->count on cat3 after evacuation');
$t->app->dumper($cat3->evacuate_to(1));

done_testing();
