# vim:set sw=4 ts=4 sts=4 ft=perl expandtab:
use Mojo::Base -strict, -signatures;
use Mojolicious;
use Dolomon::Command::theme;
use Try::Tiny;

use Test::More;
use Test::Mojo;

use FindBin qw($Bin);

$| = 1;

my ($cfile, $t);

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

my $config_file = Mojo::File->new($cfile->to_abs->to_string);
my $config_orig = $config_file->slurp;

Mojo::File->new('exports')->remove_tree     if -d 'exports';
Mojo::File->new('imports')->remove_tree     if -d 'imports';
Mojo::File->new('themes/test')->remove_tree if -d 'themes/test';

test();

$t->test('is', Dolomon::Command::theme->run('test', 1), 'OK',                                   'Create test theme');
$t->test('is', Dolomon::Command::theme->run('test', 1), 'test theme already exists. Aborting.', 'Test already exists');
$t->test('is', Dolomon::Command::theme->run('', 1),     'Undefined or empty name',               'Empty name');

my $config_theme = $config_orig;
   $config_theme =~ s/#theme.*/theme => 'test',/m;
$config_file->spurt($config_theme);

test();

Mojo::File->new('themes/test/templates')->remove_tree;
Mojo::File->new('themes/test/public')->remove_tree;

test();

Mojo::File->new('themes/test')->remove_tree if -d 'themes/test';
restore_config();

my $config_contact = $config_orig;
   $config_contact =~ s/^ +contact/#/m;
$config_file->spurt($config_contact);

test('No contact information');

restore_config();

my $config_admin = $config_orig;
   $config_admin =~ s/^ +admins/#/m;
$config_file->spurt($config_admin);

test_login('leela', 'leela');

$t->app->pg->db->query('TRUNCATE users CASCADE;');
$t->app->pg->db->query('ALTER SEQUENCE users_id_seq RESTART WITH 1;');
$t->app->pg->db->query('ALTER SEQUENCE categories_id_seq RESTART WITH 1;');

restore_config();

done_testing();

sub test ($should_fail = 0) {
    TODO: {
        todo_skip $should_fail, 3 if $should_fail;

        $t = Test::Mojo->new('Dolomon');

        $t->get_ok('/')
          ->status_is(200)
          ->content_like(qr@Dolomon.*LDAP@s);
    }
}

sub restore_config {
    $config_file->spurt($config_orig);
}

sub test_login ($login, $pass) {
    my $token = '';

    $t->post_ok('/' => form => { login => $login, password => $pass, csrf_token => $token, method => 'ldap' })
      ->status_is(200)
      ->content_like(qr@Bad CSRF token@);

    $token = $t->ua->get('/')->res->dom->find('input[name="csrf_token"]')->first->attr('value');

    $t->post_ok('/' => form => { login => $login, password => $pass, csrf_token => $token, method => 'ldap' })
      ->status_is(200)
      ->content_like(qr@$login.planetexpress\.com@)
      ->text_like('#dolo_nb' => qr@\d+@)
      ->text_like('#cat_nb'  => qr@\d+@)
      ->text_like('#tag_nb'  => qr@\d+@)
      ->text_like('#app_nb'  => qr@\d+@);

    $t->get_ok('/')
      ->status_is(302)
      ->header_is(Location => '/dashboard');
}
