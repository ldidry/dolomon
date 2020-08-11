# vim:set sw=4 ts=4 sts=4 ft=perl expandtab:
use Mojo::Base -strict, -signatures;
use Mojo::JSON qw(true false);
use Mojolicious;
use DateTime;
use DateTime::Format::Pg;

use Test::More;
use Test::Mojo;

use FindBin qw($Bin);

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

my $config_file = Mojo::File->new($cfile->to_abs->to_string);
my $config_orig = $config_file->slurp;

my $dates = {};

my $t = Test::Mojo->new('Dolomon');

## Let's go
$t->get_ok('/')
  ->status_is(200)
  ->content_like(qr@Dolomon.*LDAP@s);

$t->get_ok('/dashboard')
  ->status_is(404);

test_change_lang();
test_api_ping(0);

test_login('zoidberg', 'zoidberg');
test_api_ping(1);

test_dashboard(0, 1, 0, 0, 0);

test_account_management();

test_admin(0);

test_api_cat();
test_api_tag();
test_api_app();
test_api_dolo();

test_import_export();

test_api_cat_2();
test_api_tag_2();

test_cat();
test_tag();
test_app();
test_dolo();

test_logout();

test_login('leela', 'leela');
test_admin(1, 0);

test_logout();
test_register_account();
test_login('foobar', 'foobarbazquux', 'standard');
test_account_management(1);
test_logout();

done_testing();

######
### Functions
##
sub test_change_lang {
    $t->get_ok('/about')
      ->status_is(200)
      ->content_like(qr@It means DOwnLOad MONitor\.@);

    $t->get_ok('/lang/fr')
      ->status_is(302);

    $t->get_ok('/about')
      ->status_is(200)
      ->content_like(qr@Cela signifie DOwnLOad MONitor\.@);

    $t->get_ok('/lang/en')
      ->status_is(302);
}

sub test_api_ping ($should_success = 0){
    if ($should_success) {
        $t->get_ok('/api/ping')
          ->status_is(200)
          ->json_is({ success => true });
    } else {
        $t->get_ok('/api/ping')
          ->status_is(404);
    }
}

sub test_login ($login, $pass, $method = 'ldap') {
    my $token = '';

    $t->post_ok('/' => form => { login => $login, password => $pass, csrf_token => $token, method => $method })
      ->status_is(200)
      ->content_like(qr@Bad CSRF token@);

    $token = $t->ua->get('/')->res->dom->find('#signin input[name="csrf_token"]')->first->attr('value');

    my $regex = qr@$login.planetexpress\.com@;
       $regex = qr@validaddress.mail\.example\.org@ if $method ne 'ldap';
    $t->post_ok('/' => form => { login => $login, password => $pass, csrf_token => $token, method => $method })
      ->status_is(200)
      ->content_like($regex)
      ->text_like('#dolo_nb' => qr@\d+@)
      ->text_like('#cat_nb'  => qr@\d+@)
      ->text_like('#tag_nb'  => qr@\d+@)
      ->text_like('#app_nb'  => qr@\d+@);

    $t->get_ok('/')
      ->status_is(302)
      ->header_is(Location => '/dashboard');
}

sub test_logout {
    $t->ua->max_redirects(1);
    $t->get_ok('/logout')
      ->status_is(200)
      ->content_like(qr@You have been successfully disconnected\.@);
    $t->ua->max_redirects(0);

    $t->get_ok('/dashboard')
      ->status_is(404);

    $t->get_ok('/')
      ->status_is(200)
      ->content_like(qr@Dolomon.*LDAP@s);
}

sub test_dashboard ($d, $c, $ta, $a, $h) {
    $t->get_ok('/dashboard')
      ->status_is(200)
      ->text_like('#dolo_nb' => qr@^$d$@)
      ->text_like('#cat_nb' => qr@^$c$@)
      ->text_like('#tag_nb' => qr@^$ta$@)
      ->text_like('#app_nb' => qr@^$a$@)
      ->text_like('#total_hits' => qr@^$h$@);
}

sub test_admin ($should_success = 0, $skip = 1) {
    if ($should_success) {
        $t->get_ok('/admin')
          ->status_is(200)
          ->text_is('#main-container > h1'   => 'Administration')
          ->text_is('a[href="/admin/minion"]'=> 'See job queue');

        $t->get_ok('/admin/minion')
          ->status_is(200)
          ->content_like(qr@Minion Version.*Pg.*Backend.*Uptime in Days.*Days of Results.*Processed Jobs.*Delayed Jobs@s)
          ->text_is('h3' => 'Real-time');

        return if $skip;

        $t->get_ok('/api/admin/users')
          ->status_is(200)
          ->json_is('/dir'                  => 'DESC')
          ->json_is('/nb'                   => '10')
          ->json_is('/nb_pages'             => 1)
          ->json_is('/page'                 => '1')
          ->json_is('/sort_by'              => 'dolos_nb')
          ->json_like('/timestamp'          => qr@\d{10}@)
          ->json_is('/users/0/confirmed'    => 1)
          ->json_is('/users/0/dolos_nb'     => 3)
          ->json_is('/users/0/first_name'   => 'John')
          ->json_is('/users/0/id'           => 1)
          ->json_is('/users/0/last_name'    => 'Zoidberg')
          ->json_is('/users/0/login'        => 'zoidberg')
          ->json_is('/users/0/mail'         => 'zoidberg@planetexpress.com')
          ->json_like('/users/0/last_login' => qr@\d{10}\.\d{1,6}@)
          ->json_is('/users/1/confirmed'    => 1)
          ->json_is('/users/1/dolos_nb'     => 3)
          ->json_is('/users/1/first_name'   => 'Philip')
          ->json_is('/users/1/id'           => 3)
          ->json_is('/users/1/last_name'    => 'Fry')
          ->json_is('/users/1/login'        => 'fry')
          ->json_is('/users/1/mail'         => 'fry@planetexpress.com')
          ->json_like('/users/1/last_login' => qr@\d{10}\.\d{1,6}@)
          ->json_is('/users/2/confirmed'    => 1)
          ->json_is('/users/2/dolos_nb'     => 0)
          ->json_is('/users/2/first_name'   => 'Leela')
          ->json_is('/users/2/id'           => 2)
          ->json_is('/users/2/last_name'    => 'Turanga')
          ->json_is('/users/2/login'        => 'leela')
          ->json_is('/users/2/mail'         => 'leela@planetexpress.com')
          ->json_like('/users/2/last_login' => qr@\d{10}\.\d{1,6}@)
          ->json_is('/users/3'              => undef);

        $t->get_ok('/api/admin/users?dir=ASC')
          ->status_is(200)
          ->json_is('/dir'                  => 'ASC')
          ->json_is('/nb'                   => '10')
          ->json_is('/nb_pages'             => 1)
          ->json_is('/page'                 => '1')
          ->json_is('/sort_by'              => 'dolos_nb')
          ->json_like('/timestamp'          => qr@\d{10}@)
          ->json_is('/users/0/confirmed'    => 1)
          ->json_is('/users/0/dolos_nb'     => 0)
          ->json_is('/users/0/first_name'   => 'Leela')
          ->json_is('/users/0/id'           => 2)
          ->json_is('/users/0/last_name'    => 'Turanga')
          ->json_is('/users/0/login'        => 'leela')
          ->json_is('/users/0/mail'         => 'leela@planetexpress.com')
          ->json_like('/users/0/last_login' => qr@\d{10}\.\d{1,6}@)
          ->json_is('/users/1/confirmed'    => 1)
          ->json_is('/users/1/dolos_nb'     => 3)
          ->json_is('/users/1/first_name'   => 'John')
          ->json_is('/users/1/id'           => 1)
          ->json_is('/users/1/last_name'    => 'Zoidberg')
          ->json_is('/users/1/login'        => 'zoidberg')
          ->json_is('/users/1/mail'         => 'zoidberg@planetexpress.com')
          ->json_like('/users/1/last_login' => qr@\d{10}\.\d{1,6}@)
          ->json_is('/users/2/confirmed'    => 1)
          ->json_is('/users/2/dolos_nb'     => 3)
          ->json_is('/users/2/first_name'   => 'Philip')
          ->json_is('/users/2/id'           => 3)
          ->json_is('/users/2/last_name'    => 'Fry')
          ->json_is('/users/2/login'        => 'fry')
          ->json_is('/users/2/mail'         => 'fry@planetexpress.com')
          ->json_like('/users/2/last_login' => qr@\d{10}\.\d{1,6}@)
          ->json_is('/users/3'              => undef);

        $t->get_ok('/api/admin/users?sort_by=id')
          ->status_is(200)
          ->json_is('/dir'                  => 'DESC')
          ->json_is('/nb'                   => '10')
          ->json_is('/nb_pages'             => 1)
          ->json_is('/page'                 => '1')
          ->json_is('/sort_by'              => 'id')
          ->json_like('/timestamp'          => qr@\d{10}@)
          ->json_is('/users/0/confirmed'    => 1)
          ->json_is('/users/0/dolos_nb'     => 3)
          ->json_is('/users/0/first_name'   => 'Philip')
          ->json_is('/users/0/id'           => 3)
          ->json_is('/users/0/last_name'    => 'Fry')
          ->json_is('/users/0/login'        => 'fry')
          ->json_is('/users/0/mail'         => 'fry@planetexpress.com')
          ->json_like('/users/0/last_login' => qr@\d{10}\.\d{1,6}@)
          ->json_is('/users/1/confirmed'    => 1)
          ->json_is('/users/1/dolos_nb'     => 0)
          ->json_is('/users/1/first_name'   => 'Leela')
          ->json_is('/users/1/id'           => 2)
          ->json_is('/users/1/last_name'    => 'Turanga')
          ->json_is('/users/1/login'        => 'leela')
          ->json_is('/users/1/mail'         => 'leela@planetexpress.com')
          ->json_like('/users/1/last_login' => qr@\d{10}\.\d{1,6}@)
          ->json_is('/users/2/confirmed'    => 1)
          ->json_is('/users/2/dolos_nb'     => 3)
          ->json_is('/users/2/first_name'   => 'John')
          ->json_is('/users/2/id'           => 1)
          ->json_is('/users/2/last_name'    => 'Zoidberg')
          ->json_is('/users/2/login'        => 'zoidberg')
          ->json_is('/users/2/mail'         => 'zoidberg@planetexpress.com')
          ->json_like('/users/2/last_login' => qr@\d{10}\.\d{1,6}@)
          ->json_is('/users/3'              => undef);

        $t->get_ok('/api/admin/users?sort_by=last_login&dir=ASC&nb=1')
          ->status_is(200)
          ->json_is('/dir'                  => 'ASC')
          ->json_is('/nb'                   => '1')
          ->json_is('/nb_pages'             => 3)
          ->json_is('/page'                 => '1')
          ->json_is('/sort_by'              => 'last_login')
          ->json_like('/timestamp'          => qr@\d{10}@)
          ->json_is('/users/0/confirmed'    => 1)
          ->json_is('/users/0/dolos_nb'     => 3)
          ->json_is('/users/0/first_name'   => 'Philip')
          ->json_is('/users/0/id'           => 3)
          ->json_is('/users/0/last_name'    => 'Fry')
          ->json_is('/users/0/login'        => 'fry')
          ->json_is('/users/0/mail'         => 'fry@planetexpress.com')
          ->json_like('/users/0/last_login' => qr@\d{10}\.\d{1,6}@)
          ->json_is('/users/1'              => undef);

        $t->get_ok('/api/admin/users?search=zoid')
          ->status_is(200)
          ->json_is('/dir'                  => 'DESC')
          ->json_is('/nb'                   => '10')
          ->json_is('/nb_pages'             => 1)
          ->json_is('/page'                 => '1')
          ->json_is('/sort_by'              => 'dolos_nb')
          ->json_like('/timestamp'          => qr@\d{10}@)
          ->json_is('/users/0/confirmed'    => 1)
          ->json_is('/users/0/dolos_nb'     => 3)
          ->json_is('/users/0/first_name'   => 'John')
          ->json_is('/users/0/id'           => 1)
          ->json_is('/users/0/last_name'    => 'Zoidberg')
          ->json_is('/users/0/login'        => 'zoidberg')
          ->json_is('/users/0/mail'         => 'zoidberg@planetexpress.com')
          ->json_like('/users/0/last_login' => qr@\d{10}\.\d{1,6}@)
          ->json_is('/users/2'              => undef);

        $t->delete_ok('/api/admin/users' => form => { id => 42 })
          ->json_is({
            msg => {
                title => 'Error',
                class => 'alert-danger',
                text  => 'Unable to find an account with this id.'
            },
            success => false
          });

      $t->delete_ok('/api/admin/users' => form => { id => 3 })
        ->json_is({
          msg => {
              title => 'Success',
              class => 'alert-info',
              text  => 'The account fry will be deleted in a short time.',
          },
          success => true
        });

      $t->get_ok('/api/admin/users')
        ->status_is(200)
        ->json_is('/dir'                  => 'DESC')
        ->json_is('/nb'                   => '10')
        ->json_is('/nb_pages'             => 1)
        ->json_is('/page'                 => '1')
        ->json_is('/sort_by'              => 'dolos_nb')
        ->json_like('/timestamp'          => qr@\d{10}@)
        ->json_is('/users/0/confirmed'    => 1)
        ->json_is('/users/0/dolos_nb'     => 3)
        ->json_is('/users/0/first_name'   => 'John')
        ->json_is('/users/0/id'           => 1)
        ->json_is('/users/0/last_name'    => 'Zoidberg')
        ->json_is('/users/0/login'        => 'zoidberg')
        ->json_is('/users/0/mail'         => 'zoidberg@planetexpress.com')
        ->json_like('/users/0/last_login' => qr@\d{10}\.\d{1,6}@)
        ->json_is('/users/1/confirmed'    => 1)
        ->json_is('/users/1/dolos_nb'     => 3)
        ->json_is('/users/1/first_name'   => 'Philip')
        ->json_is('/users/1/id'           => 3)
        ->json_is('/users/1/last_name'    => 'Fry')
        ->json_is('/users/1/login'        => 'fry')
        ->json_is('/users/1/mail'         => 'fry@planetexpress.com')
        ->json_like('/users/1/last_login' => qr@\d{10}\.\d{1,6}@)
        ->json_is('/users/2/confirmed'    => 1)
        ->json_is('/users/2/dolos_nb'     => 0)
        ->json_is('/users/2/first_name'   => 'Leela')
        ->json_is('/users/2/id'           => 2)
        ->json_is('/users/2/last_name'    => 'Turanga')
        ->json_is('/users/2/login'        => 'leela')
        ->json_is('/users/2/mail'         => 'leela@planetexpress.com')
        ->json_like('/users/2/last_login' => qr@\d{10}\.\d{1,6}@)
        ->json_is('/users/3'              => undef);

      $t->app->minion->perform_jobs;

      $t->get_ok('/api/admin/users')
        ->status_is(200)
        ->json_is('/dir'                  => 'DESC')
        ->json_is('/nb'                   => '10')
        ->json_is('/nb_pages'             => 1)
        ->json_is('/page'                 => '1')
        ->json_is('/sort_by'              => 'dolos_nb')
        ->json_like('/timestamp'          => qr@\d{10}@)
        ->json_is('/users/0/confirmed'    => 1)
        ->json_is('/users/0/dolos_nb'     => 3)
        ->json_is('/users/0/first_name'   => 'John')
        ->json_is('/users/0/id'           => 1)
        ->json_is('/users/0/last_name'    => 'Zoidberg')
        ->json_is('/users/0/login'        => 'zoidberg')
        ->json_is('/users/0/mail'         => 'zoidberg@planetexpress.com')
        ->json_like('/users/0/last_login' => qr@\d{10}\.\d{1,6}@)
        ->json_is('/users/1/confirmed'    => 1)
        ->json_is('/users/1/dolos_nb'     => 0)
        ->json_is('/users/1/first_name'   => 'Leela')
        ->json_is('/users/1/id'           => 2)
        ->json_is('/users/1/last_name'    => 'Turanga')
        ->json_is('/users/1/login'        => 'leela')
        ->json_is('/users/1/mail'         => 'leela@planetexpress.com')
        ->json_like('/users/1/last_login' => qr@\d{10}\.\d{1,6}@)
        ->json_is('/users/2'              => undef);

    } else {
        $t->get_ok('/admin')
          ->status_is(404);
    }
}

sub test_api_cat {
    $t->get_ok('/api/cat')
      ->status_is(200)
      ->json_is({
        object => [
            {
                dolos => [],
                id    => 1,
                name  => 'Default'
            }
        ],
        success => true
    });

    $t->post_ok('/api/cat')
      ->status_is(200)
      ->json_is({
        msg     => 'Category name blank or undefined. I refuse to create a category without name.',
        success => false
      });

    $t->post_ok('/api/cat', form => { name => 'foo' })
      ->status_is(200)
      ->json_is({
        msg     => 'The category foo has been successfully created.',
        object  => {
            dolos => [],
            id    => 2,
            name  => 'foo'
        },
        success => true
      });

    $t->get_ok('/api/cat', form => { id => 2 })
      ->status_is(200)
      ->json_is({
        object  => {
            dolos => [],
            id    => 2,
            name  => 'foo'
        },
        success => true
      });

    $t->get_ok('/api/cat')
      ->status_is(200)
      ->json_is({
        object => [
            {
                dolos => [],
                id    => 1,
                name  => 'Default'
            },
            {
                dolos => [],
                id    => 2,
                name  => 'foo'
            }
        ],
        success => true
      });

    $t->put_ok('/api/cat', form => { name => 'foobar' })
      ->status_is(200)
      ->json_is({
        msg     => 'The category you\'re trying to rename does not belong to you.',
        success => false
      });

    $t->put_ok('/api/cat', form => { id => 42, name => 'foobar' })
      ->status_is(200)
      ->json_is({
        msg     => 'The category you\'re trying to rename does not belong to you.',
        success => false
      });

    $t->put_ok('/api/cat', form => { id => 2 })
      ->status_is(200)
      ->json_is({
        msg     => 'New category name blank or undefined. I refuse to rename the category.',
        success => false
      });

    $t->put_ok('/api/cat', form => { id => 2, name => '' })
      ->status_is(200)
      ->json_is({
        msg     => 'New category name blank or undefined. I refuse to rename the category.',
        success => false
      });

    $t->put_ok('/api/cat', form => { id => 2, name => 'foo' })
      ->status_is(200)
      ->json_is({
        msg     => 'The new name is the same as the previous: foo.',
        success => false
      });

    $t->put_ok('/api/cat', form => { id => 2, name => 'foobar' })
      ->status_is(200)
      ->json_is({
        msg     => 'The category foo has been successfully renamed to foobar',
        newname => 'foobar',
        success => true
      });

    $t->get_ok('/api/cat')
      ->status_is(200)
      ->json_is({
        object => [
            {
                dolos => [],
                id    => 1,
                name  => 'Default'
            },
            {
                dolos => [],
                id    => 2,
                name  => 'foobar'
            }
        ],
        success => true
      });

    $t->delete_ok('/api/cat', form => { id => 42 })
      ->status_is(200)
      ->json_is({
        msg     => 'The category you\'re trying to delete does not belong to you.',
        success => false
      });

    $t->delete_ok('/api/cat', form => { id => 2 })
      ->status_is(200)
      ->json_is({
        msg     => 'The category foobar has been successfully deleted.',
        success => true
      });

    $t->get_ok('/api/cat')
      ->status_is(200)
      ->json_is({
        object => [
            {
                dolos => [],
                id    => 1,
                name  => 'Default'
            }
        ],
        success => true
    });

    test_logout();
    test_login('leela', 'leela');
    test_admin(1);

    $t->get_ok('/api/cat')
      ->status_is(200)
      ->json_is({
        object => [
            {
                dolos => [],
                id    => 3,
                name  => 'Default'
            }
        ],
        success => true
    });

    $t->post_ok('/api/cat', form => { name => 'garply' })
      ->status_is(200)
      ->json_is({
        msg     => 'The category garply has been successfully created.',
        object  => {
            dolos => [],
            id    => 4,
            name  => 'garply'
        },
        success => true
      });

    test_logout();
    test_login('zoidberg', 'zoidberg');
}

sub test_api_tag {
    $t->get_ok('/api/tag')
      ->status_is(200)
      ->json_is({
        object => [],
        success => true
    });

    $t->post_ok('/api/tag')
      ->status_is(200)
      ->json_is({
        msg     => 'Tag name blank or undefined. I refuse to create a tag without name.',
        success => false
      });

    $t->post_ok('/api/tag', form => { name => 'bar' })
      ->status_is(200)
      ->json_is({
        msg     => 'The tag bar has been successfully created.',
        object  => {
            dolos => [],
            id    => 1,
            name  => 'bar'
        },
        success => true
      });

    $t->get_ok('/api/tag', form => { id => 1 })
      ->status_is(200)
      ->json_is({
        object  => {
            dolos => [],
            id    => 1,
            name  => 'bar'
        },
        success => true
      });

    $t->get_ok('/api/tag')
      ->status_is(200)
      ->json_is({
        object => [
            {
                dolos => [],
                id    => 1,
                name  => 'bar'
            },
        ],
        success => true
      });

    $t->put_ok('/api/tag', form => { name => 'barbaz' })
      ->status_is(200)
      ->json_is({
        msg     => 'The tag you\'re trying to rename does not belong to you.',
        success => false
      });

    $t->put_ok('/api/tag', form => { id => 42, name => 'barbaz' })
      ->status_is(200)
      ->json_is({
        msg     => 'The tag you\'re trying to rename does not belong to you.',
        success => false
      });

    $t->put_ok('/api/tag', form => { id => 1 })
      ->status_is(200)
      ->json_is({
        msg     => 'New tag name blank or undefined. I refuse to rename the tag.',
        success => false
      });

    $t->put_ok('/api/tag', form => { id => 1, name => '' })
      ->status_is(200)
      ->json_is({
        msg     => 'New tag name blank or undefined. I refuse to rename the tag.',
        success => false
      });

    $t->put_ok('/api/tag', form => { id => 1, name => 'bar' })
      ->status_is(200)
      ->json_is({
        msg     => 'The new name is the same as the previous: bar.',
        success => false
      });

    $t->put_ok('/api/tag', form => { id => 1, name => 'barbaz' })
      ->status_is(200)
      ->json_is({
        msg     => 'The tag bar has been successfully renamed to barbaz',
        newname => 'barbaz',
        success => true
      });

    $t->get_ok('/api/tag')
      ->status_is(200)
      ->json_is({
        object => [
            {
                dolos => [],
                id    => 1,
                name  => 'barbaz'
            }
        ],
        success => true
      });

    $t->delete_ok('/api/tag', form => { id => 42 })
      ->status_is(200)
      ->json_is({
        msg     => 'The tag you\'re trying to delete does not belong to you.',
        success => false
      });

    $t->delete_ok('/api/tag', form => { id => 1 })
      ->status_is(200)
      ->json_is({
        msg     => 'The tag barbaz has been successfully deleted.',
        success => true
      });

    $t->get_ok('/api/tag')
      ->status_is(200)
      ->json_is({
        object => [],
        success => true
    });

    $t->post_ok('/api/tag', form => { name => 'quux' })
      ->status_is(200)
      ->json_is({
        msg     => 'The tag quux has been successfully created.',
        object  => {
            dolos => [],
            id    => 2,
            name  => 'quux'
        },
        success => true
      });

    $t->post_ok('/api/tag', form => { name => 'corge' })
      ->status_is(200)
      ->json_is({
        msg     => 'The tag corge has been successfully created.',
        object  => {
            dolos => [],
            id    => 3,
            name  => 'corge'
        },
        success => true
      });

    test_logout();
    test_login('leela', 'leela');

    $t->post_ok('/api/tag', form => { name => 'waldo' })
      ->status_is(200)
      ->json_is({
        msg     => 'The tag waldo has been successfully created.',
        object  => {
            dolos => [],
            id    => 4,
            name  => 'waldo'
        },
        success => true
      });

    test_logout();
    test_login('zoidberg', 'zoidberg');
}

sub test_api_app {
    $t->get_ok('/api/app')
      ->status_is(200)
      ->json_is({
        object => [],
        success => true
    });

    $t->post_ok('/api/app')
      ->status_is(200)
      ->json_is({
        msg     => 'Application name blank or undefined. I refuse to create an application without name.',
        success => false
      });

    $t->post_ok('/api/app', form => { name => 'baz' })
      ->status_is(200)
      ->json_like('/msg' => qr@^The application baz has been successfully created\. Please note the credentials below: you won\'t be able to recover them\.<br><ul><li>app_id: [0-9a-z]{8}-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{12}</li><li>app_secret: [0-9a-z]{8}-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{12}</li><ul>@)
      ->json_is('/object'  => { id => 1, name => 'baz' })
      ->json_is('/success' => true);

    $t->get_ok('/api/app', form => { id => 1 })
      ->status_is(200)
      ->json_is({
        object => {
            id    => 1,
            name  => 'baz'
        },
        success => true
      });

    $t->get_ok('/api/app')
      ->status_is(200)
      ->json_is({
        object => [
            {
                id    => 1,
                name  => 'baz'
            }
        ],
        success => true
      });

    $t->put_ok('/api/app', form => { name => 'bazqux' })
      ->status_is(200)
      ->json_is({
        msg     => 'The application you\'re trying to rename does not belong to you.',
        success => false
      });

    $t->put_ok('/api/app', form => { id => 42, name => 'bazqux' })
      ->status_is(200)
      ->json_is({
        msg     => 'The application you\'re trying to rename does not belong to you.',
        success => false
      });

    $t->put_ok('/api/app', form => { id => 1 })
      ->status_is(200)
      ->json_is({
        msg     => 'New application name blank or undefined. I refuse to rename the application.',
        success => false
      });

    $t->put_ok('/api/app', form => { id => 1, name => '' })
      ->status_is(200)
      ->json_is({
        msg     => 'New application name blank or undefined. I refuse to rename the application.',
        success => false
      });

    $t->put_ok('/api/app', form => { id => 1, name => 'baz' })
      ->status_is(200)
      ->json_is({
        msg     => 'The new name is the same as the previous: baz.',
        success => false
      });

    $t->put_ok('/api/app', form => { id => 1, name => 'bazqux' })
      ->status_is(200)
      ->json_is({
        msg     => 'The application baz has been successfully renamed to bazqux',
        newname => 'bazqux',
        success => true
      });

    $t->get_ok('/api/app')
      ->status_is(200)
      ->json_is({
        object => [
            {
                id    => 1,
                name  => 'bazqux'
            }
        ],
        success => true
      });

    $t->delete_ok('/api/app', form => { id => 42 })
      ->status_is(200)
      ->json_is({
        msg     => 'The application you\'re trying to delete does not belong to you.',
        success => false
      });

    $t->delete_ok('/api/app', form => { id => 1 })
      ->status_is(200)
      ->json_is({
        msg     => 'The application bazqux has been successfully deleted.',
        success => true
      });

    $t->get_ok('/api/app')
      ->status_is(200)
      ->json_is({
        object => [],
        success => true
    });

    $t->post_ok('/api/app', form => { name => 'grault' })
      ->status_is(200)
      ->json_like('/msg' => qr@^The application grault has been successfully created\. Please note the credentials below: you won\'t be able to recover them\.<br><ul><li>app_id: [0-9a-z]{8}-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{12}</li><li>app_secret: [0-9a-z]{8}-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{12}</li><ul>@)
      ->json_is('/object'  => { id => 2, name => 'grault' })
      ->json_is('/success' => true);
}

sub test_api_dolo {
    $t->get_ok('/api/dolo')
      ->status_is(200)
      ->json_is({
        object  => [],
        success => true
      });

    $t->post_ok('/api/dolo')
      ->status_is(200)
      ->json_is({
        errors  => {
            catList => [ 'I can\'t find the given category.' ],
            doloUrl => [ 'The url is not a valid http, https, ftp or ftps URL.' ]
        },
        success => false
      });

    $t->post_ok('/api/dolo', form => { url => 'https://foo.dolomon.org' })
      ->status_is(200)
      ->json_is({
        errors  => {
            catList => [ 'I can\'t find the given category.' ]
        },
        success => false
      });

    $t->post_ok('/api/dolo', form => { url => 'https://foo.dolomon.org', cat_id => 3 })
      ->status_is(200)
      ->json_is({
        errors  => {
            catList => [ 'The category you want to use for your dolo does not belong to you.' ]
        },
        success => false
      });

    $t->post_ok('/api/dolo', form => { cat_id => 1 })
      ->status_is(200)
      ->json_is({
        errors  => {
            doloUrl => [ 'The url is not a valid http, https, ftp or ftps URL.' ]
        },
        success => false
      });

    $t->post_ok('/api/dolo', form => { cat_id => 1, url => 'meh' })
      ->status_is(200)
      ->json_is({
        errors  => {
            doloUrl => [ 'The url is not a valid http, https, ftp or ftps URL.' ]
        },
        success => false
      });

    for my $bad ('a', -1, 1.5) {
        $t->post_ok('/api/dolo', form => { initial_count => $bad })
          ->status_is(200)
          ->json_is({
            errors  => {
                catList      => [ 'I can\'t find the given category.' ],
                doloUrl      => [ 'The url is not a valid http, https, ftp or ftps URL.' ],
                initialCount => [ 'The initial counter must be an integer, superior or equal to 0.' ]
            },
            success => false
          });
    }

    $t->post_ok('/api/dolo', form => {
           url           => 'https://foo.dolomon.org',
           cat_id        => 1,
           name          => 'fred',
           short         => 'fred',
           initial_count => 5,
           extra         => 'plugh'
      })
      ->status_is(200)
      ->json_like('/msg'               => qr@^The dolo fred has been successfully created.<br>Its dolomon URL is .+\.$@)
      ->json_like('/object/created_at' => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,6}@)
      ->json_is('/object/expired'       => 0)
      ->json_is('/object/expires_after' => undef)
      ->json_is('/object/expires_at'    => undef)
      ->json_is('/object/extra'         => 'plugh')
      ->json_is('/object/expires_after' => undef)
      ->json_is('/object/category_id'   => 1)
      ->json_is('/object/id'            => 1)
      ->json_is('/object/count'         => 5)
      ->json_is('/object/initial_count' => 5)
      ->json_is('/object/name'          => 'fred')
      ->json_is('/object/parent_id'     => undef)
      ->json_is('/object/short'         => '/h/fred')
      ->json_is('/object/tags'          => [])
      ->json_is('/object/url'           => 'https://foo.dolomon.org')
      ->json_is('/success'              => true);

    $t->get_ok('/api/dolo', form => { id => 1 })
      ->status_is(200)
      ->json_like('/object/created_at' => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,6}@)
      ->json_is('/object/expired'       => 0)
      ->json_is('/object/expires_after' => undef)
      ->json_is('/object/expires_at'    => undef)
      ->json_is('/object/extra'         => 'plugh')
      ->json_is('/object/expires_after' => undef)
      ->json_is('/object/category_id'   => 1)
      ->json_is('/object/id'            => 1)
      ->json_is('/object/count'         => 5)
      ->json_is('/object/initial_count' => 5)
      ->json_is('/object/name'          => 'fred')
      ->json_is('/object/parent_id'     => undef)
      ->json_is('/object/short'         => '/h/fred')
      ->json_is('/object/tags'          => [])
      ->json_is('/object/url'           => 'https://foo.dolomon.org')
      ->json_is('/success'              => true);

    $t->get_ok('/h/fred')
      ->status_is(302)
      ->header_is(Location => 'https://foo.dolomon.org');

    $t->post_ok('/api/dolo', form => {
           url       => 'https://foo.dolomon.org',
           cat_id    => 1,
           name      => 'fred',
           short     => 'fred',
           parent_id => 42
      })
      ->status_is(200)
      ->json_is({
        errors  => {
            doloUrl    => [ 'You already have that URL in the dolos of this category.' ],
            doloName   => [ 'The name fred is already taken for the category you choose.' ],
            doloParent => [ 'The parent_id you provided is not suitable for use: it does not belong to you or is already a child dolo.' ]
        },
        success => false
      });

    $t->post_ok('/api/dolo', form => {
           url           => 'https://bar.dolomon.org',
           cat_id        => 1,
           name          => 'xyzzy',
           short         => 'xyzzy',
           initial_count => 3,
           extra         => 'thud'
      })
      ->status_is(200)
      ->json_like('/msg'               => qr@^The dolo xyzzy has been successfully created.<br>Its dolomon URL is .+\.$@)
      ->json_like('/object/created_at' => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,6}@)
      ->json_is('/object/expired'       => 0)
      ->json_is('/object/expires_after' => undef)
      ->json_is('/object/expires_at'    => undef)
      ->json_is('/object/extra'         => 'thud')
      ->json_is('/object/expires_after' => undef)
      ->json_is('/object/category_id'   => 1)
      ->json_is('/object/id'            => 2)
      ->json_is('/object/count'         => 3)
      ->json_is('/object/initial_count' => 3)
      ->json_is('/object/name'          => 'xyzzy')
      ->json_is('/object/parent_id'     => undef)
      ->json_is('/object/short'         => '/h/xyzzy')
      ->json_is('/object/tags'          => [])
      ->json_is('/object/url'           => 'https://bar.dolomon.org')
      ->json_is('/success'              => true);

    $t->put_ok('/api/dolo')
      ->status_is(200)
      ->json_is({
        errors  => {
            id => [ 'You need to provide a dolo id!' ]
        },
        success => false
      });

    $t->put_ok('/api/dolo', form => { id => 42 })
      ->status_is(200)
      ->json_is({
        errors  => {
            id => [ 'The dolo you’re trying to modify does not belong to you.' ]
        },
        success => false
      });

    $t->put_ok('/api/dolo', form => {
           id  => 1,
           url => 'foo.bar.baz',
      })
      ->status_is(200)
      ->json_is({
        errors  => {
            doloUrl => [ 'The url is not a valid http, https, ftp or ftps URL.' ],
            catList => [ 'I can\'t find the given category.' ]
        },
        success => false
      });

    $t->put_ok('/api/dolo', form => {
           id       => 1,
           cat_id   => 3,
           'tags[]' => [4, 42]
      })
      ->status_is(200)
      ->json_is({
        errors  => {
            doloUrl => [ 'The url is not a valid http, https, ftp or ftps URL.' ],
            catList => [ 'The category you want to use for your dolo does not belong to you.' ],
            tagList => [
                'At least one of the tag you want to use for your dolo does not belong to you.',
                'I can\'t find at least one of the given tag.'
            ]
        },
        success => false
      });

    $t->put_ok('/api/dolo', form => {
           id        => 1,
           cat_id    => 1,
           url       => 'https://bar.dolomon.org',
           parent_id => 42,
           name      => 'xyzzy'
      })
      ->status_is(200)
      ->json_is({
        errors  => {
            doloName   => [ 'The name xyzzy is already taken for the category you choose.' ],
            doloUrl    => [ 'You already have that URL in the dolos of this category.' ],
            doloParent => [ 'The parent_id you provided is not suitable for use: it does not belong to you or is already a child dolo.' ]
        },
        success => false
      });

    $t->put_ok('/api/dolo', form => {
           id       => 1,
           url      => 'https://baz.dolomon.org',
           name     => 'waldo',
           extra    => 'xyzzy',
           cat_id   => 1,
           'tags[]' => [2, 3],
      })
      ->status_is(200)
      ->json_like('/object/created_at'  => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,6}@)
      ->json_is('/msg'                  => 'The dolo waldo has been successfully modified.')
      ->json_is('/object/expired'       => 0)
      ->json_is('/object/expires_after' => undef)
      ->json_is('/object/expires_at'    => undef)
      ->json_is('/object/extra'         => 'xyzzy')
      ->json_is('/object/expires_after' => undef)
      ->json_is('/object/category_id'   => 1)
      ->json_is('/object/id'            => 1)
      ->json_is('/object/count'         => 5)
      ->json_is('/object/initial_count' => 5)
      ->json_is('/object/name'          => 'waldo')
      ->json_is('/object/parent_id'     => undef)
      ->json_is('/object/short'         => '/h/fred')
      ->json_is('/object/tags'          => [2, 3])
      ->json_is('/object/url'           => 'https://baz.dolomon.org')
      ->json_is('/success'              => true);

    $t->get_ok('/api/dolo', form => { id => 1 })
      ->status_is(200)
      ->json_like('/object/created_at' => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,6}@)
      ->json_is('/object/expired'       => 0)
      ->json_is('/object/expires_after' => undef)
      ->json_is('/object/expires_at'    => undef)
      ->json_is('/object/extra'         => 'xyzzy')
      ->json_is('/object/expires_after' => undef)
      ->json_is('/object/category_id'   => 1)
      ->json_is('/object/id'            => 1)
      ->json_is('/object/count'         => 5)
      ->json_is('/object/initial_count' => 5)
      ->json_is('/object/name'          => 'waldo')
      ->json_is('/object/parent_id'     => undef)
      ->json_is('/object/short'         => '/h/fred')
      ->json_is('/object/tags'          => [
            {
                id   => 3,
                name => 'corge'
            },
            {
                id   => 2,
                name => 'quux'
            }
        ])
      ->json_is('/object/url'           => 'https://baz.dolomon.org')
      ->json_is('/success'              => true);

    $t->get_ok('/api/dolo/data/42')
      ->status_is(200)
      ->json_is({
        msg     => 'The dolo you\'re trying to get does not belong to you.',
        success => false,
      });

    $t->get_ok('/api/dolo/data/1?period=years')
      ->status_is(200)
      ->json_like('/object/created_at'  => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,6}@)
      ->json_is('/data'                 => [])
      ->json_is('/max'                  => undef)
      ->json_is('/min'                  => undef)
      ->json_is('/object/expired'       => 0)
      ->json_is('/object/expires_after' => undef)
      ->json_is('/object/expires_at'    => undef)
      ->json_is('/object/extra'         => 'xyzzy')
      ->json_is('/object/expires_after' => undef)
      ->json_is('/object/category_id'   => 1)
      ->json_is('/object/id'            => 1)
      ->json_is('/object/count'         => 5)
      ->json_is('/object/initial_count' => 5)
      ->json_is('/object/name'          => 'waldo')
      ->json_is('/object/parent_id'     => undef)
      ->json_is('/object/short'         => '/h/fred')
      ->json_is('/object/tags'          => [
            {
                id   => 3,
                name => 'corge'
            },
            {
                id   => 2,
                name => 'quux'
            }
        ])
      ->json_is('/object/url'           => 'https://baz.dolomon.org')
      ->json_is('/success'              => true);

    my $dt  = DateTime->from_epoch(epoch => time);
       $dt  = DateTime->new(
       year       => $dt->year(),
       month      => $dt->month(),
       day        => $dt->day(),
       hour       => 8,
       minute     => 15,
       second     => 42,
    );
    my $dow = $dt->day_of_week();
    $t->app->pg->db->query('SELECT increment_dolo_cascade(?, ?, ?, ?, ?, ?, ?)', 1, $dt->year(), $dt->month(), $dt->week_number(), $dt->day(), DateTime::Format::Pg->format_timestamp_with_time_zone($dt), 'https://dolomon.org');
    $dates->{base} = {
        year  => $dt->year(),
        month => $dt->month(),
        week  => $dt->week_number(),
        day   => $dt->day()
    };
    $dt->subtract(minutes => 1);
    $t->app->pg->db->query('SELECT increment_dolo_cascade(?, ?, ?, ?, ?, ?, ?)', 1, $dt->year(), $dt->month(), $dt->week_number(), $dt->day(), DateTime::Format::Pg->format_timestamp_with_time_zone($dt), 'https://dolomon.org');
    $dates->{minutes} = {
        year  => $dt->year(),
        month => $dt->month(),
        week  => $dt->week_number(),
        day   => $dt->day()
    };
    if ($dow == 1) {
        $dt->subtract(minutes => 2);
    } else {
        $dt->subtract(days => 1)
    }
    $t->app->pg->db->query('SELECT increment_dolo_cascade(?, ?, ?, ?, ?, ?, ?)', 1, $dt->year(), $dt->month(), $dt->week_number(), $dt->day(), DateTime::Format::Pg->format_timestamp_with_time_zone($dt), 'https://dolomon.org');
    $dates->{days} = {
        year  => $dt->year(),
        month => $dt->month(),
        week  => $dt->week_number(),
        day   => $dt->day()
    };
    $dt->subtract(weeks => 1);
    $t->app->pg->db->query('SELECT increment_dolo_cascade(?, ?, ?, ?, ?, ?, ?)', 1, $dt->year(), $dt->month(), $dt->week_number(), $dt->day(), DateTime::Format::Pg->format_timestamp_with_time_zone($dt), 'https://dolomon.org');
    $dates->{weeks} = {
        year  => $dt->year(),
        month => $dt->month(),
        week  => $dt->week_number(),
        day   => $dt->day()
    };
    $dt->subtract(months => 1);
    $t->app->pg->db->query('SELECT increment_dolo_cascade(?, ?, ?, ?, ?, ?, ?)', 1, $dt->year(), $dt->month(), $dt->week_number(), $dt->day(), DateTime::Format::Pg->format_timestamp_with_time_zone($dt), 'https://dolomon.org');
    $dates->{months} = {
        year  => $dt->year(),
        month => $dt->month(),
        week  => $dt->week_number(),
        day   => $dt->day()
    };
    $dt->subtract(years => 1);
    $t->app->pg->db->query('SELECT increment_dolo_cascade(?, ?, ?, ?, ?, ?, ?)', 1, $dt->year(), $dt->month(), $dt->week_number(), $dt->day(), DateTime::Format::Pg->format_timestamp_with_time_zone($dt), 'https://dolomon.org');
    $dates->{years} = {
        year  => $dt->year(),
        month => $dt->month(),
        week  => $dt->week_number(),
        day   => $dt->day()
    };

    $t->get_ok('/api/dolo/data/1?period=years')
      ->status_is(200)
      ->json_like('/object/created_at'  => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,6}@)
      ->json_like('/max'                => qr@\d{10}@)
      ->json_like('/min'                => qr@\d{10}@)
      ->json_like('/data/0/x'           => qr@\d{10}@)
      ->json_like('/data/1/x'           => qr@\d{10}@)
      ->json_is('/data/2'               => undef)
      ->json_is('/data/0/value'         => 1)
      ->json_is('/data/1/value'         => 5)
      ->json_is('/object/expired'       => 0)
      ->json_is('/object/expires_after' => undef)
      ->json_is('/object/expires_at'    => undef)
      ->json_is('/object/extra'         => 'xyzzy')
      ->json_is('/object/expires_after' => undef)
      ->json_is('/object/category_id'   => 1)
      ->json_is('/object/id'            => 1)
      ->json_is('/object/count'         => 11)
      ->json_is('/object/initial_count' => 5)
      ->json_is('/object/name'          => 'waldo')
      ->json_is('/object/parent_id'     => undef)
      ->json_is('/object/short'         => '/h/fred')
      ->json_is('/object/tags'          => [
            {
                id   => 3,
                name => 'corge'
            },
            {
                id   => 2,
                name => 'quux'
            }
        ])
      ->json_is('/object/url'           => 'https://baz.dolomon.org')
      ->json_is('/success'              => true);

    $t->get_ok('/api/dolo/data/1?period=months')
      ->status_is(200)
      ->json_like('/object/created_at'  => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,6}@)
      ->json_like('/max'                => qr@\d{10}@)
      ->json_like('/min'                => qr@\d{10}@)
      ->json_like('/data/0/x'           => qr@\d{10}@)
      ->json_like('/data/1/x'           => qr@\d{10}@)
      ->json_like('/data/2/x'           => qr@\d{10}@)
      ->json_is('/data/3'               => undef)
      ->json_is('/data/0/value'         => 1)
      ->json_is('/data/1/value'         => 1)
      ->json_is('/data/2/value'         => 4)
      ->json_is('/object/expired'       => 0)
      ->json_is('/object/expires_after' => undef)
      ->json_is('/object/expires_at'    => undef)
      ->json_is('/object/extra'         => 'xyzzy')
      ->json_is('/object/expires_after' => undef)
      ->json_is('/object/category_id'   => 1)
      ->json_is('/object/id'            => 1)
      ->json_is('/object/count'         => 11)
      ->json_is('/object/initial_count' => 5)
      ->json_is('/object/name'          => 'waldo')
      ->json_is('/object/parent_id'     => undef)
      ->json_is('/object/short'         => '/h/fred')
      ->json_is('/object/tags'          => [
            {
                id   => 3,
                name => 'corge'
            },
            {
                id   => 2,
                name => 'quux'
            }
        ])
      ->json_is('/object/url'           => 'https://baz.dolomon.org')
      ->json_is('/success'              => true);

    $t->get_ok('/api/dolo/data/1?period=weeks')
      ->status_is(200)
      ->json_like('/object/created_at'  => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,6}@)
      ->json_like('/max'                => qr@\d{10}@)
      ->json_like('/min'                => qr@\d{10}@)
      ->json_like('/data/0/x'           => qr@\d{10}@)
      ->json_like('/data/1/x'           => qr@\d{10}@)
      ->json_like('/data/2/x'           => qr@\d{10}@)
      ->json_like('/data/3/x'           => qr@\d{10}@)
      ->json_is('/data/4'               => undef)
      ->json_is('/data/0/value'         => 1)
      ->json_is('/data/1/value'         => 1)
      ->json_is('/data/2/value'         => 1)
      ->json_is('/data/3/value'         => 3)
      ->json_is('/object/expired'       => 0)
      ->json_is('/object/expires_after' => undef)
      ->json_is('/object/expires_at'    => undef)
      ->json_is('/object/extra'         => 'xyzzy')
      ->json_is('/object/expires_after' => undef)
      ->json_is('/object/category_id'   => 1)
      ->json_is('/object/id'            => 1)
      ->json_is('/object/count'         => 11)
      ->json_is('/object/initial_count' => 5)
      ->json_is('/object/name'          => 'waldo')
      ->json_is('/object/parent_id'     => undef)
      ->json_is('/object/short'         => '/h/fred')
      ->json_is('/object/tags'          => [
            {
                id   => 3,
                name => 'corge'
            },
            {
                id   => 2,
                name => 'quux'
            }
        ])
      ->json_is('/object/url'           => 'https://baz.dolomon.org')
      ->json_is('/success'              => true);

    $t->get_ok('/api/dolo/data/1?period=days')
      ->status_is(200)
      ->json_like('/object/created_at'  => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,6}@)
      ->json_like('/max'                => qr@\d{10}@)
      ->json_like('/min'                => qr@\d{10}@)
      ->json_like('/data/0/x'           => qr@\d{10}@)
      ->json_like('/data/1/x'           => qr@\d{10}@)
      ->json_like('/data/2/x'           => qr@\d{10}@)
      ->json_like('/data/3/x'           => qr@\d{10}@)
      ->json_like('/data/4/x'           => qr@\d{10}@)
      ->json_is('/data/5'               => undef)
      ->json_is('/data/0/value'         => 1)
      ->json_is('/data/1/value'         => 1)
      ->json_is('/data/2/value'         => 1)
      ->json_is('/data/3/value'         => 1)
      ->json_is('/data/4/value'         => 2)
      ->json_is('/object/expired'       => 0)
      ->json_is('/object/expires_after' => undef)
      ->json_is('/object/expires_at'    => undef)
      ->json_is('/object/extra'         => 'xyzzy')
      ->json_is('/object/expires_after' => undef)
      ->json_is('/object/category_id'   => 1)
      ->json_is('/object/id'            => 1)
      ->json_is('/object/count'         => 11)
      ->json_is('/object/initial_count' => 5)
      ->json_is('/object/name'          => 'waldo')
      ->json_is('/object/parent_id'     => undef)
      ->json_is('/object/short'         => '/h/fred')
      ->json_is('/object/tags'          => [
            {
                id   => 3,
                name => 'corge'
            },
            {
                id   => 2,
                name => 'quux'
            }
        ])
      ->json_is('/object/url'           => 'https://baz.dolomon.org')
      ->json_is('/success'              => true);

    $t->get_ok('/api/dolo/data/1?period=hits')
      ->status_is(200)
      ->json_like('/object/created_at'  => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,6}@)
      ->json_like('/max'                => qr@\d{10}@)
      ->json_like('/min'                => qr@\d{10}@)
      ->json_like('/data/0/x'           => qr@\d{10}@)
      ->json_like('/data/1/x'           => qr@\d{10}@)
      ->json_like('/data/2/x'           => qr@\d{10}@)
      ->json_like('/data/3/x'           => qr@\d{10}@)
      ->json_like('/data/4/x'           => qr@\d{10}@)
      ->json_is('/data/5'               => undef)
      ->json_is('/data/0/value'         => 1)
      ->json_is('/data/1/value'         => 1)
      ->json_is('/data/2/value'         => 1)
      ->json_is('/data/3/value'         => 1)
      ->json_is('/data/4/value'         => 2)
      ->json_is('/object/expired'       => 0)
      ->json_is('/object/expires_after' => undef)
      ->json_is('/object/expires_at'    => undef)
      ->json_is('/object/extra'         => 'xyzzy')
      ->json_is('/object/expires_after' => undef)
      ->json_is('/object/category_id'   => 1)
      ->json_is('/object/id'            => 1)
      ->json_is('/object/count'         => 11)
      ->json_is('/object/initial_count' => 5)
      ->json_is('/object/name'          => 'waldo')
      ->json_is('/object/parent_id'     => undef)
      ->json_is('/object/short'         => '/h/fred')
      ->json_is('/object/tags'          => [
            {
                id   => 3,
                name => 'corge'
            },
            {
                id   => 2,
                name => 'quux'
            }
        ])
      ->json_is('/object/url'           => 'https://baz.dolomon.org')
      ->json_is('/success'              => true);

    $t->get_ok('/api/dolo/data/1?period=hits&aggregate_by=1')
      ->status_is(200)
      ->json_like('/object/created_at'  => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,6}@)
      ->json_like('/max'                => qr@\d{10}@)
      ->json_like('/min'                => qr@\d{10}@)
      ->json_like('/data/0/x'           => qr@\d{10}@)
      ->json_like('/data/1/x'           => qr@\d{10}@)
      ->json_like('/data/2/x'           => qr@\d{10}@)
      ->json_like('/data/3/x'           => qr@\d{10}@)
      ->json_like('/data/4/x'           => qr@\d{10}@)
      ->json_like('/data/5/x'           => qr@\d{10}@)
      ->json_is('/data/6'               => undef)
      ->json_is('/data/0/value'         => 1)
      ->json_is('/data/1/value'         => 1)
      ->json_is('/data/2/value'         => 1)
      ->json_is('/data/3/value'         => 1)
      ->json_is('/data/4/value'         => 1)
      ->json_is('/data/5/value'         => 1)
      ->json_is('/object/expired'       => 0)
      ->json_is('/object/expires_after' => undef)
      ->json_is('/object/expires_at'    => undef)
      ->json_is('/object/extra'         => 'xyzzy')
      ->json_is('/object/expires_after' => undef)
      ->json_is('/object/category_id'   => 1)
      ->json_is('/object/id'            => 1)
      ->json_is('/object/count'         => 11)
      ->json_is('/object/initial_count' => 5)
      ->json_is('/object/name'          => 'waldo')
      ->json_is('/object/parent_id'     => undef)
      ->json_is('/object/short'         => '/h/fred')
      ->json_is('/object/tags'          => [
            {
                id   => 3,
                name => 'corge'
            },
            {
                id   => 2,
                name => 'quux'
            }
        ])
      ->json_is('/object/url'           => 'https://baz.dolomon.org')
      ->json_is('/success'              => true);

    $t->post_ok('/api/dolo', form => {
           url           => 'https://foo.dolomon.org',
           cat_id        => 1,
           name          => 'plugh',
           short         => 'plugh',
           initial_count => 0,
           parent_id     => 2,
           extra         => 'plugh'
      })
      ->status_is(200)
      ->json_like('/msg'               => qr@^The dolo plugh has been successfully created.<br>Its dolomon URL is .+\.$@)
      ->json_like('/object/created_at' => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,6}@)
      ->json_is('/object/expired'       => 0)
      ->json_is('/object/expires_after' => undef)
      ->json_is('/object/expires_at'    => undef)
      ->json_is('/object/extra'         => 'plugh')
      ->json_is('/object/expires_after' => undef)
      ->json_is('/object/category_id'   => 1)
      ->json_is('/object/id'            => 3)
      ->json_is('/object/count'         => 0)
      ->json_is('/object/initial_count' => 0)
      ->json_is('/object/name'          => 'plugh')
      ->json_is('/object/parent_id'     => 2)
      ->json_is('/object/short'         => '/h/plugh')
      ->json_is('/object/tags'          => [])
      ->json_is('/object/url'           => 'https://foo.dolomon.org')
      ->json_is('/success'              => true);

    $t->get_ok('/api/dolo/zip/42')
      ->status_is(200)
      ->json_is({
        msg     => 'The dolo you\'re trying to get does not belong to you.',
        success => false,
      });

    $t->get_ok('/api/dolo/zip/1')
      ->status_is(200)
      ->content_type_is('application/zip;name=export-dolo-1.zip')
      ->header_is('Content-Disposition' => 'attachment;filename=export-dolo-1.zip');
}

sub test_import_export {
    $t->app->minion->enqueue('clean_stats');
    $t->app->minion->perform_jobs;

    $t->get_ok('/export-import')
      ->status_is(200)
      ->text_is('#main-container > h1'              => "\n    Data export\n")
      ->text_is('a[href="/export"]'                 => "\n        \n        Export your data\n    ")
      ->text_is('#main-container h1:nth-of-type(2)' => "\n    Data import\n")
      ->text_is('button[type="submit"]'             => "\n        \n        Import data\n    ")
      ->content_unlike(qr@Exports available to download:@);

    $t->ua->max_redirects(1);
    $t->get_ok('/export')
      ->status_is(200)
      ->text_is('.alert strong' =>  'Your data export is about to be processed.')
      ->content_like(qr@You have 1 data export\(s\) waiting to be processed@)
      ->content_like(qr@alert-info.*You will receive a mail with a link to download your data once ready. You will be able to retrieve the export on this page\.@s);
    $t->ua->max_redirects(0);

    $t->app->minion->perform_jobs;

    $t->get_ok('/export-import')
      ->status_is(200)
      ->text_is('#main-container > h1'              => "\n    Data export\n")
      ->text_is('a[href="/export"]'                 => "\n        \n        Export your data\n    ")
      ->text_is('#main-container h1:nth-of-type(2)' => "\n    Data import\n")
      ->text_is('button[type="submit"]'             => "\n        \n        Import data\n    ")
      ->text_is('h2'                                => "\n    Exports available to download:\n")
      ->text_like('.data-export-link'               => qr@/data/[0-9a-z]{8}-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{12}.json@);

    my $data_export_link = $t->ua->get('/export-import')->res->dom->find('.data-export-link')->[0]->attr('href');
    $t->get_ok($data_export_link)
      ->status_is(200)
      ->json_like('/applications/0/app_id'     => qr@[0-9a-z]{8}-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{12}@)
      ->json_like('/applications/0/app_secret' => qr@[0-9a-z]{8}-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{12}@)
      ->json_is('/applications/0/id'           => 2)
      ->json_is('/applications/0/name'         => 'grault')
      ->json_is('/applications/0/user_id'      => 1)
      ->json_is('/user_count'            => 15)
      ->json_is('/categories'            => [{ id => 1, name => 'Default', user_id => 1 }])
      ->json_is('/dolo_has_tags'         => [{ dolo_id => 1, tag_id => 2 }, { dolo_id => 1, tag_id => 3 }])
      ->json_like('/dolos/0/created_at'  => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,6}@)
      ->json_is('/dolos/0/category_id'   => 1)
      ->json_is('/dolos/0/count'         => 12)
      ->json_is('/dolos/0/expired'       => 0)
      ->json_is('/dolos/0/expires_after' => undef)
      ->json_is('/dolos/0/expires_at'    => undef)
      ->json_is('/dolos/0/extra'         => 'xyzzy')
      ->json_is('/dolos/0/id'            => 1)
      ->json_is('/dolos/0/initial_count' => 5)
      ->json_is('/dolos/0/name'          => 'waldo')
      ->json_is('/dolos/0/parent_id'     => undef)
      ->json_is('/dolos/0/short'         => 'fred')
      ->json_is('/dolos/0/url'           => 'https://baz.dolomon.org')
      ->json_like('/dolos/1/created_at'  => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,6}@)
      ->json_is('/dolos/1/category_id'   => 1)
      ->json_is('/dolos/1/count'         => 3)
      ->json_is('/dolos/1/expired'       => 0)
      ->json_is('/dolos/1/expires_after' => undef)
      ->json_is('/dolos/1/expires_at'    => undef)
      ->json_is('/dolos/1/extra'         => 'thud')
      ->json_is('/dolos/1/id'            => 2)
      ->json_is('/dolos/1/initial_count' => 3)
      ->json_is('/dolos/1/name'          => 'xyzzy')
      ->json_is('/dolos/1/parent_id'     => undef)
      ->json_is('/dolos/1/short'         => 'xyzzy')
      ->json_is('/dolos/1/url'           => 'https://bar.dolomon.org')
      ->json_is('/dolos_day' => [
            {
                count   => 3,
                day     => $dates->{base}->{day},
                dolo_id => 1,
                id      => 1,
                month   => $dates->{base}->{month},
                week    => $dates->{base}->{week},
                year    => $dates->{base}->{year}
            },
            {
                count   => 1,
                day     => $dates->{days}->{day},
                dolo_id => 1,
                id      => 3,
                month   => $dates->{days}->{month},
                week    => $dates->{days}->{week},
                year    => $dates->{days}->{year}
            },
            {
                count   => 1,
                day     => $dates->{weeks}->{day},
                dolo_id => 1,
                id      => 4,
                month   => $dates->{weeks}->{month},
                week    => $dates->{weeks}->{week},
                year    => $dates->{weeks}->{year}
            },
            {
                count   => 1,
                day     => $dates->{months}->{day},
                dolo_id => 1,
                id      => 5,
                month   => $dates->{months}->{month},
                week    => $dates->{months}->{week},
                year    => $dates->{months}->{year}
            },
        ])
      ->json_like('/dolos_hits/0/ts'     => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\+\d{2}@)
      ->json_is('/dolos_hits/0/dolo_id'  => 1)
      ->json_is('/dolos_hits/0/id'       => 1)
      ->json_is('/dolos_hits/0/referrer' => 'https://dolomon.org')
      ->json_like('/dolos_hits/1/ts'     => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\+\d{2}@)
      ->json_is('/dolos_hits/1/dolo_id'  => 1)
      ->json_is('/dolos_hits/1/id'       => 2)
      ->json_is('/dolos_hits/1/referrer' => 'https://dolomon.org')
      ->json_like('/dolos_hits/2/ts'     => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\+\d{2}@)
      ->json_is('/dolos_hits/2/dolo_id'  => 1)
      ->json_is('/dolos_hits/2/id'       => 3)
      ->json_is('/dolos_hits/2/referrer' => 'https://dolomon.org')
      ->json_like('/dolos_hits/3/ts'     => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\+\d{2}@)
      ->json_is('/dolos_hits/3/dolo_id'  => 1)
      ->json_is('/dolos_hits/3/id'       => 7)
      ->json_is('/dolos_hits/3/referrer' => undef)
      ->json_is('/dolos_hits/4'          => undef)
      ->json_is('/dolos_month' =>[
        { count => 5, dolo_id => 1, id => 1, month => $dates->{weeks}->{month},  year => $dates->{weeks}->{year}  },
        { count => 1, dolo_id => 1, id => 5, month => $dates->{months}->{month}, year => $dates->{months}->{year} },
        { count => 1, dolo_id => 1, id => 6, month => $dates->{years}->{month},  year => $dates->{years}->{year}  }
      ])
      ->json_is('/dolos_week' => [
        { count => 4, dolo_id => 1, id => 1, week => $dates->{base}->{week},   year => $dates->{base}->{year}   },
        { count => 1, dolo_id => 1, id => 4, week => $dates->{weeks}->{week},  year => $dates->{weeks}->{year}  },
        { count => 1, dolo_id => 1, id => 5, week => $dates->{months}->{week}, year => $dates->{months}->{year} },
      ])
      ->json_is('/dolos_year' => [
        { count => 6, dolo_id => 1, id => 1, year => $dates->{base}->{year}  },
        { count => 1, dolo_id => 1, id => 6, year => $dates->{years}->{year} }
      ])
      ->json_is('/tags' => [
        { id => 2, name => 'quux',  user_id => 1 },
        { id => 3, name => 'corge', user_id => 1 }
      ]);

    my $jsonexport = $t->ua->get($data_export_link)->res->body;
    test_logout();
    test_login('fry', 'fry');

    $t->get_ok('/export-import')
      ->status_is(200)
      ->text_is('#main-container > h1'              => "\n    Data export\n")
      ->text_is('a[href="/export"]'                 => "\n        \n        Export your data\n    ")
      ->text_is('#main-container h1:nth-of-type(2)' => "\n    Data import\n")
      ->text_is('button[type="submit"]'             => "\n        \n        Import data\n    ")
      ->content_unlike(qr@Exports available to download:@);

    test_dashboard(0, 1, 0, 0, 0);

    $t->ua->max_redirects(1);
    $t->post_ok('/import' => form => { file => { content => $jsonexport, filename => 'export.json' } })
      ->status_is(200)
      ->content_like(qr@alert-info.*Your data import is about to be processed\..*You will receive a mail once your file has been processed\.@s);
    $t->ua->max_redirects(0);

    test_dashboard(0, 1, 0, 0, 0);

    $t->app->minion->perform_jobs;

    test_dashboard(3, 2, 2, 1, 15);

    test_logout();
    test_login('zoidberg', 'zoidberg');
}

sub test_cat {
    $t->get_ok('/cat')
      ->status_is(200)
      ->text_is('a[aria-controls="collapse1"]' => "\n                    Default\n                ")
      ->text_is('#cat_badge_1'                 => '2 dolo(s)')
      ->text_like('#cat_id_1 #dolo_id_1 .durl' => qr@.*/h/fred$@)
      ->text_is('#cat_id_1 #dolo_id_1 .url'    => 'https://baz.dolomon.org')
      ->text_is('#cat_id_1 #dolo_id_1 .name'   => 'waldo')
      ->text_is('#cat_id_1 #dolo_id_1 .extra'  => 'xyzzy')
      ->text_is('#cat_id_1 #dolo_id_1 .hits'   => 12)
      ->text_like('#cat_id_1 #dolo_id_2 .durl' => qr@.*/h/xyzzy$@)
      ->text_is('#cat_id_1 #dolo_id_2 .url'    => 'https://bar.dolomon.org')
      ->text_is('#cat_id_1 #dolo_id_2 .name'   => 'xyzzy')
      ->text_is('#cat_id_1 #dolo_id_2 .extra'  => 'thud')
      ->text_is('#cat_id_1 #dolo_id_2 .hits'   => 3);

    $t->get_ok('/cat/1')
      ->status_is(200)
      ->content_like(qr@<h1>.*Default@s)
      ->text_is('#main-container > p' => "\n     15\n")
      ->text_like('#cat_id_1 #dolo_id_1 .durl' => qr@.*/h/fred$@)
      ->text_is('#cat_id_1 #dolo_id_1 .url'    => 'https://baz.dolomon.org')
      ->text_is('#cat_id_1 #dolo_id_1 .name'   => 'waldo')
      ->text_is('#cat_id_1 #dolo_id_1 .extra'  => 'xyzzy')
      ->text_is('#cat_id_1 #dolo_id_1 .hits'   => 12)
      ->text_like('#cat_id_1 #dolo_id_2 .durl' => qr@.*/h/xyzzy$@)
      ->text_is('#cat_id_1 #dolo_id_2 .url'    => 'https://bar.dolomon.org')
      ->text_is('#cat_id_1 #dolo_id_2 .name'   => 'xyzzy')
      ->text_is('#cat_id_1 #dolo_id_2 .extra'  => 'thud')
      ->text_is('#cat_id_1 #dolo_id_2 .hits'   => 3);
}

sub test_tag {
    $t->get_ok('/tags')
      ->status_is(200)
      ->text_is('a[aria-controls="collapse1"]' => "\n                    quux\n                ")
      ->text_is('#tag_badge_2'                 => '1 dolo(s)')
      ->text_like('#tag_id_2 #dolo_id_1 .durl' => qr@.*/h/fred$@)
      ->text_is('#tag_id_2 #dolo_id_1 .url'    => 'https://baz.dolomon.org')
      ->text_is('#tag_id_2 #dolo_id_1 .name'   => 'waldo')
      ->text_is('#tag_id_2 #dolo_id_1 .extra'  => 'xyzzy')
      ->text_is('#tag_id_2 #dolo_id_1 .hits'   => 12)
      ->text_is('a[aria-controls="collapse2"]' => "\n                    corge\n                ")
      ->text_like('#tag_id_3 #dolo_id_1 .durl' => qr@.*/h/fred$@)
      ->text_is('#tag_id_3 #dolo_id_1 .url'    => 'https://baz.dolomon.org')
      ->text_is('#tag_id_3 #dolo_id_1 .name'   => 'waldo')
      ->text_is('#tag_id_3 #dolo_id_1 .extra'  => 'xyzzy')
      ->text_is('#tag_id_3 #dolo_id_1 .hits'   => 12);

    $t->get_ok('/tag/2')
      ->status_is(200)
      ->content_like(qr@<h1>.*quux@s)
      ->text_is('#main-container > p' => "\n     12\n")
      ->text_like('#tag_id_2 #dolo_id_1 .durl' => qr@.*/h/fred$@)
      ->text_is('#tag_id_2 #dolo_id_1 .url'    => 'https://baz.dolomon.org')
      ->text_is('#tag_id_2 #dolo_id_1 .name'   => 'waldo')
      ->text_is('#tag_id_2 #dolo_id_1 .extra'  => 'xyzzy')
      ->text_is('#tag_id_2 #dolo_id_1 .hits'   => 12);

    $t->get_ok('/tag/3')
      ->status_is(200)
      ->content_like(qr@<h1>.*corge@s)
      ->text_is('#main-container > p' => "\n     12\n")
      ->text_like('#tag_id_3 #dolo_id_1 .durl' => qr@.*/h/fred$@)
      ->text_is('#tag_id_3 #dolo_id_1 .url'    => 'https://baz.dolomon.org')
      ->text_is('#tag_id_3 #dolo_id_1 .name'   => 'waldo')
      ->text_is('#tag_id_3 #dolo_id_1 .extra'  => 'xyzzy')
      ->text_is('#tag_id_3 #dolo_id_1 .hits'   => 12);
}

sub test_app {
    $t->get_ok('/apps')
      ->status_is(200)
      ->text_is('.name' => "grault\n                    \n                ")
      ->element_exists('a[data-id="2"]');
}

sub test_dolo {
    $t->get_ok('/dolo')
      ->status_is(200)
      ->text_is('#dolo_id_1 .url'         => 'https://baz.dolomon.org')
      ->text_is('#dolo_id_1 .name'        => 'waldo')
      ->text_is('#dolo_id_1 .extra'       => 'xyzzy')
      ->text_is('#dolo_id_1 .hits'        => 12)
      ->text_is('#dolo_id_1 .expired'     => 'No')
      ->text_is('#dolo_id_1 .will-expire' => 'No')
      ->text_is('#dolo_id_2 .url'         => 'https://bar.dolomon.org')
      ->text_is('#dolo_id_2 .name'        => 'xyzzy')
      ->text_is('#dolo_id_2 .extra'       => 'thud')
      ->text_is('#dolo_id_2 .hits'        => 3)
      ->text_is('#dolo_id_2 .expired'     => 'No')
      ->text_is('#dolo_id_2 .will-expire' => 'No');

    $t->get_ok('/dolo/1')
      ->status_is(200)
      ->text_is('.show-dolo h1'                     => ' waldo')
      ->text_is('a[href="/cat/1"]'                  => 'Default')
      ->text_is('a[href="https://baz.dolomon.org"]' => 'https://baz.dolomon.org')
      ->text_like('a[href$="/h/fred"]'              => qr@^http.*/h/fred@)
      ->content_like(qr@12 hits@s);

    $t->get_ok('/dolo/2')
      ->status_is(200)
      ->text_is('.show-dolo h1'                     => ' xyzzy')
      ->text_is('a[href="/cat/1"]'                  => 'Default')
      ->text_is('a[href="https://bar.dolomon.org"]' => 'https://bar.dolomon.org')
      ->text_like('a[href$="/h/xyzzy"]'             => qr@^http.*/h/xyzzy@)
      ->content_like(qr@3 hits@s);
}

sub test_api_cat_2 {
    $t->get_ok('/api/cat/data/1?period=years')
      ->status_is(200)
      ->json_like('/object/dolos/0/created_at'  => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,6}@)
      ->json_like('/object/dolos/1/created_at'  => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,6}@)
      ->json_like('/max'                        => qr@\d{10}@)
      ->json_like('/min'                        => qr@\d{10}@)
      ->json_like('/data/0/x'                   => qr@\d{10}@)
      ->json_like('/data/1/x'                   => qr@\d{10}@)
      ->json_is('/data/2'                       => undef)
      ->json_is('/data/0/value'                 => 1)
      ->json_is('/data/1/value'                 => 6)
      ->json_is('/object/id'                    => 1)
      ->json_is('/object/name'                  => 'Default')
      ->json_is('/object/dolos/2'               => undef)
      ->json_is('/object/dolos/0/expired'       => undef)
      ->json_is('/object/dolos/0/expires_after' => undef)
      ->json_is('/object/dolos/0/expires_at'    => undef)
      ->json_is('/object/dolos/0/extra'         => 'xyzzy')
      ->json_is('/object/dolos/0/expires_after' => undef)
      ->json_is('/object/dolos/0/category_id'   => 1)
      ->json_is('/object/dolos/0/category_name' => 'Default')
      ->json_is('/object/dolos/0/id'            => 1)
      ->json_is('/object/dolos/0/count'         => 12)
      ->json_is('/object/dolos/0/name'          => 'waldo')
      ->json_is('/object/dolos/0/parent_id'     => undef)
      ->json_is('/object/dolos/0/short'         => '/h/fred')
      ->json_is('/object/dolos/0/url'           => 'https://baz.dolomon.org')
      ->json_is('/object/dolos/0/tags'          => [
            {
                id   => 3,
                name => 'corge'
            },
            {
                id   => 2,
                name => 'quux'
            }
        ])
      ->json_is('/object/dolos/1/expired'       => undef)
      ->json_is('/object/dolos/1/expires_after' => undef)
      ->json_is('/object/dolos/1/expires_at'    => undef)
      ->json_is('/object/dolos/1/extra'         => 'thud')
      ->json_is('/object/dolos/1/expires_after' => undef)
      ->json_is('/object/dolos/1/category_id'   => 1)
      ->json_is('/object/dolos/1/category_name' => 'Default')
      ->json_is('/object/dolos/1/id'            => 2)
      ->json_is('/object/dolos/1/count'         => 3)
      ->json_is('/object/dolos/1/name'          => 'xyzzy')
      ->json_is('/object/dolos/1/parent_id'     => undef)
      ->json_is('/object/dolos/1/short'         => '/h/xyzzy')
      ->json_is('/object/dolos/1/url'           => 'https://bar.dolomon.org')
      ->json_is('/object/dolos/1/tags'          => [])
      ->json_is('/success'                      => true);

    $t->get_ok('/api/cat/data/1?period=months')
      ->status_is(200)
      ->json_like('/object/dolos/0/created_at'  => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,6}@)
      ->json_like('/object/dolos/1/created_at'  => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,6}@)
      ->json_like('/max'                        => qr@\d{10}@)
      ->json_like('/min'                        => qr@\d{10}@)
      ->json_like('/data/0/x'                   => qr@\d{10}@)
      ->json_like('/data/1/x'                   => qr@\d{10}@)
      ->json_like('/data/2/x'                   => qr@\d{10}@)
      ->json_is('/data/3'                       => undef)
      ->json_is('/data/0/value'                 => 1)
      ->json_is('/data/1/value'                 => 1)
      ->json_is('/data/2/value'                 => 5)
      ->json_is('/object/id'                    => 1)
      ->json_is('/object/name'                  => 'Default')
      ->json_is('/object/dolos/2'               => undef)
      ->json_is('/object/dolos/0/expired'       => undef)
      ->json_is('/object/dolos/0/expires_after' => undef)
      ->json_is('/object/dolos/0/expires_at'    => undef)
      ->json_is('/object/dolos/0/extra'         => 'xyzzy')
      ->json_is('/object/dolos/0/expires_after' => undef)
      ->json_is('/object/dolos/0/category_id'   => 1)
      ->json_is('/object/dolos/0/category_name' => 'Default')
      ->json_is('/object/dolos/0/id'            => 1)
      ->json_is('/object/dolos/0/count'         => 12)
      ->json_is('/object/dolos/0/name'          => 'waldo')
      ->json_is('/object/dolos/0/parent_id'     => undef)
      ->json_is('/object/dolos/0/short'         => '/h/fred')
      ->json_is('/object/dolos/0/url'           => 'https://baz.dolomon.org')
      ->json_is('/object/dolos/0/tags'          => [
            {
                id   => 3,
                name => 'corge'
            },
            {
                id   => 2,
                name => 'quux'
            }
        ])
      ->json_is('/object/dolos/1/expired'       => undef)
      ->json_is('/object/dolos/1/expires_after' => undef)
      ->json_is('/object/dolos/1/expires_at'    => undef)
      ->json_is('/object/dolos/1/extra'         => 'thud')
      ->json_is('/object/dolos/1/expires_after' => undef)
      ->json_is('/object/dolos/1/category_id'   => 1)
      ->json_is('/object/dolos/1/category_name' => 'Default')
      ->json_is('/object/dolos/1/id'            => 2)
      ->json_is('/object/dolos/1/count'         => 3)
      ->json_is('/object/dolos/1/name'          => 'xyzzy')
      ->json_is('/object/dolos/1/parent_id'     => undef)
      ->json_is('/object/dolos/1/short'         => '/h/xyzzy')
      ->json_is('/object/dolos/1/url'           => 'https://bar.dolomon.org')
      ->json_is('/object/dolos/1/tags'          => [])
      ->json_is('/success'                      => true);

    $t->get_ok('/api/cat/data/1?period=weeks')
      ->status_is(200)
      ->json_like('/object/dolos/0/created_at'  => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,6}@)
      ->json_like('/object/dolos/1/created_at'  => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,6}@)
      ->json_like('/max'                        => qr@\d{10}@)
      ->json_like('/min'                        => qr@\d{10}@)
      ->json_like('/data/0/x'                   => qr@\d{10}@)
      ->json_like('/data/1/x'                   => qr@\d{10}@)
      ->json_like('/data/2/x'                   => qr@\d{10}@)
      ->json_is('/data/3'                       => undef)
      ->json_is('/data/0/value'                 => 1)
      ->json_is('/data/1/value'                 => 1)
      ->json_is('/data/2/value'                 => 4)
      ->json_is('/object/id'                    => 1)
      ->json_is('/object/name'                  => 'Default')
      ->json_is('/object/dolos/2'               => undef)
      ->json_is('/object/dolos/0/expired'       => undef)
      ->json_is('/object/dolos/0/expires_after' => undef)
      ->json_is('/object/dolos/0/expires_at'    => undef)
      ->json_is('/object/dolos/0/extra'         => 'xyzzy')
      ->json_is('/object/dolos/0/expires_after' => undef)
      ->json_is('/object/dolos/0/category_id'   => 1)
      ->json_is('/object/dolos/0/category_name' => 'Default')
      ->json_is('/object/dolos/0/id'            => 1)
      ->json_is('/object/dolos/0/count'         => 12)
      ->json_is('/object/dolos/0/name'          => 'waldo')
      ->json_is('/object/dolos/0/parent_id'     => undef)
      ->json_is('/object/dolos/0/short'         => '/h/fred')
      ->json_is('/object/dolos/0/url'           => 'https://baz.dolomon.org')
      ->json_is('/object/dolos/0/tags'          => [
            {
                id   => 3,
                name => 'corge'
            },
            {
                id   => 2,
                name => 'quux'
            }
        ])
      ->json_is('/object/dolos/1/expired'       => undef)
      ->json_is('/object/dolos/1/expires_after' => undef)
      ->json_is('/object/dolos/1/expires_at'    => undef)
      ->json_is('/object/dolos/1/extra'         => 'thud')
      ->json_is('/object/dolos/1/expires_after' => undef)
      ->json_is('/object/dolos/1/category_id'   => 1)
      ->json_is('/object/dolos/1/category_name' => 'Default')
      ->json_is('/object/dolos/1/id'            => 2)
      ->json_is('/object/dolos/1/count'         => 3)
      ->json_is('/object/dolos/1/name'          => 'xyzzy')
      ->json_is('/object/dolos/1/parent_id'     => undef)
      ->json_is('/object/dolos/1/short'         => '/h/xyzzy')
      ->json_is('/object/dolos/1/url'           => 'https://bar.dolomon.org')
      ->json_is('/object/dolos/1/tags'          => [])
      ->json_is('/success'                      => true);

    $t->get_ok('/api/cat/data/1?period=days')
      ->status_is(200)
      ->json_like('/object/dolos/0/created_at'  => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,6}@)
      ->json_like('/object/dolos/1/created_at'  => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,6}@)
      ->json_like('/max'                        => qr@\d{10}@)
      ->json_like('/min'                        => qr@\d{10}@)
      ->json_like('/data/0/x'                   => qr@\d{10}@)
      ->json_like('/data/1/x'                   => qr@\d{10}@)
      ->json_like('/data/2/x'                   => qr@\d{10}@)
      ->json_like('/data/3/x'                   => qr@\d{10}@)
      ->json_is('/data/4'                       => undef)
      ->json_is('/data/0/value'                 => 1)
      ->json_is('/data/1/value'                 => 1)
      ->json_is('/data/2/value'                 => 1)
      ->json_is('/data/3/value'                 => 3)
      ->json_is('/object/id'                    => 1)
      ->json_is('/object/name'                  => 'Default')
      ->json_is('/object/dolos/2'               => undef)
      ->json_is('/object/dolos/0/expired'       => undef)
      ->json_is('/object/dolos/0/expires_after' => undef)
      ->json_is('/object/dolos/0/expires_at'    => undef)
      ->json_is('/object/dolos/0/extra'         => 'xyzzy')
      ->json_is('/object/dolos/0/expires_after' => undef)
      ->json_is('/object/dolos/0/category_id'   => 1)
      ->json_is('/object/dolos/0/category_name' => 'Default')
      ->json_is('/object/dolos/0/id'            => 1)
      ->json_is('/object/dolos/0/count'         => 12)
      ->json_is('/object/dolos/0/name'          => 'waldo')
      ->json_is('/object/dolos/0/parent_id'     => undef)
      ->json_is('/object/dolos/0/short'         => '/h/fred')
      ->json_is('/object/dolos/0/url'           => 'https://baz.dolomon.org')
      ->json_is('/object/dolos/0/tags'          => [
            {
                id   => 3,
                name => 'corge'
            },
            {
                id   => 2,
                name => 'quux'
            }
        ])
      ->json_is('/object/dolos/1/expired'       => undef)
      ->json_is('/object/dolos/1/expires_after' => undef)
      ->json_is('/object/dolos/1/expires_at'    => undef)
      ->json_is('/object/dolos/1/extra'         => 'thud')
      ->json_is('/object/dolos/1/expires_after' => undef)
      ->json_is('/object/dolos/1/category_id'   => 1)
      ->json_is('/object/dolos/1/category_name' => 'Default')
      ->json_is('/object/dolos/1/id'            => 2)
      ->json_is('/object/dolos/1/count'         => 3)
      ->json_is('/object/dolos/1/name'          => 'xyzzy')
      ->json_is('/object/dolos/1/parent_id'     => undef)
      ->json_is('/object/dolos/1/short'         => '/h/xyzzy')
      ->json_is('/object/dolos/1/url'           => 'https://bar.dolomon.org')
      ->json_is('/object/dolos/1/tags'          => [])
      ->json_is('/success'                      => true);

    $t->get_ok('/api/cat/data/1?period=hits')
      ->status_is(200)
      ->json_like('/object/dolos/0/created_at'  => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,6}@)
      ->json_like('/object/dolos/1/created_at'  => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,6}@)
      ->json_like('/max'                        => qr@\d{10}@)
      ->json_like('/min'                        => qr@\d{10}@)
      ->json_like('/data/0/x'                   => qr@\d{10}@)
      ->json_like('/data/1/x'                   => qr@\d{10}@)
      ->json_like('/data/2/x'                   => qr@\d{10}@)
      ->json_is('/data/3'                       => undef)
      ->json_is('/data/0/value'                 => 1)
      ->json_is('/data/1/value'                 => 2)
      ->json_is('/data/2/value'                 => 1)
      ->json_is('/object/id'                    => 1)
      ->json_is('/object/name'                  => 'Default')
      ->json_is('/object/dolos/2'               => undef)
      ->json_is('/object/dolos/0/expired'       => undef)
      ->json_is('/object/dolos/0/expires_after' => undef)
      ->json_is('/object/dolos/0/expires_at'    => undef)
      ->json_is('/object/dolos/0/extra'         => 'xyzzy')
      ->json_is('/object/dolos/0/expires_after' => undef)
      ->json_is('/object/dolos/0/category_id'   => 1)
      ->json_is('/object/dolos/0/category_name' => 'Default')
      ->json_is('/object/dolos/0/id'            => 1)
      ->json_is('/object/dolos/0/count'         => 12)
      ->json_is('/object/dolos/0/name'          => 'waldo')
      ->json_is('/object/dolos/0/parent_id'     => undef)
      ->json_is('/object/dolos/0/short'         => '/h/fred')
      ->json_is('/object/dolos/0/url'           => 'https://baz.dolomon.org')
      ->json_is('/object/dolos/0/tags'          => [
            {
                id   => 3,
                name => 'corge'
            },
            {
                id   => 2,
                name => 'quux'
            }
        ])
      ->json_is('/object/dolos/1/expired'       => undef)
      ->json_is('/object/dolos/1/expires_after' => undef)
      ->json_is('/object/dolos/1/expires_at'    => undef)
      ->json_is('/object/dolos/1/extra'         => 'thud')
      ->json_is('/object/dolos/1/expires_after' => undef)
      ->json_is('/object/dolos/1/category_id'   => 1)
      ->json_is('/object/dolos/1/category_name' => 'Default')
      ->json_is('/object/dolos/1/id'            => 2)
      ->json_is('/object/dolos/1/count'         => 3)
      ->json_is('/object/dolos/1/name'          => 'xyzzy')
      ->json_is('/object/dolos/1/parent_id'     => undef)
      ->json_is('/object/dolos/1/short'         => '/h/xyzzy')
      ->json_is('/object/dolos/1/url'           => 'https://bar.dolomon.org')
      ->json_is('/object/dolos/1/tags'          => [])
      ->json_is('/success'                      => true);

    $t->get_ok('/api/cat/data/1?period=hits&aggregate_by=1')
      ->status_is(200)
      ->json_like('/object/dolos/0/created_at'            => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,6}@)
      ->json_like('/object/dolos/1/created_at'            => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,6}@)
      ->json_like('/object/dolos/1/children/0/created_at' => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,6}@)
      ->json_like('/max'                        => qr@\d{10}@)
      ->json_like('/min'                        => qr@\d{10}@)
      ->json_like('/data/0/x'                   => qr@\d{10}@)
      ->json_like('/data/1/x'                   => qr@\d{10}@)
      ->json_like('/data/2/x'                   => qr@\d{10}@)
      ->json_like('/data/3/x'                   => qr@\d{10}@)
      ->json_is('/data/4'                       => undef)
      ->json_is('/data/0/value'                 => 1)
      ->json_is('/data/1/value'                 => 1)
      ->json_is('/data/2/value'                 => 1)
      ->json_is('/data/3/value'                 => 1)
      ->json_is('/object/id'                    => 1)
      ->json_is('/object/name'                  => 'Default')
      ->json_is('/object/dolos/2'               => undef)
      ->json_is('/object/dolos/0/expired'       => undef)
      ->json_is('/object/dolos/0/expires_after' => undef)
      ->json_is('/object/dolos/0/expires_at'    => undef)
      ->json_is('/object/dolos/0/extra'         => 'xyzzy')
      ->json_is('/object/dolos/0/expires_after' => undef)
      ->json_is('/object/dolos/0/category_id'   => 1)
      ->json_is('/object/dolos/0/category_name' => 'Default')
      ->json_is('/object/dolos/0/id'            => 1)
      ->json_is('/object/dolos/0/count'         => 12)
      ->json_is('/object/dolos/0/name'          => 'waldo')
      ->json_is('/object/dolos/0/parent_id'     => undef)
      ->json_is('/object/dolos/0/short'         => '/h/fred')
      ->json_is('/object/dolos/0/url'           => 'https://baz.dolomon.org')
      ->json_is('/object/dolos/0/tags'          => [
            {
                id   => 3,
                name => 'corge'
            },
            {
                id   => 2,
                name => 'quux'
            }
        ])
      ->json_is('/object/dolos/0/children'      => [])
      ->json_is('/object/dolos/1/expired'       => undef)
      ->json_is('/object/dolos/1/expires_after' => undef)
      ->json_is('/object/dolos/1/expires_at'    => undef)
      ->json_is('/object/dolos/1/extra'         => 'thud')
      ->json_is('/object/dolos/1/expires_after' => undef)
      ->json_is('/object/dolos/1/category_id'   => 1)
      ->json_is('/object/dolos/1/category_name' => 'Default')
      ->json_is('/object/dolos/1/id'            => 2)
      ->json_is('/object/dolos/1/count'         => 3)
      ->json_is('/object/dolos/1/name'          => 'xyzzy')
      ->json_is('/object/dolos/1/parent_id'     => undef)
      ->json_is('/object/dolos/1/short'         => '/h/xyzzy')
      ->json_is('/object/dolos/1/url'           => 'https://bar.dolomon.org')
      ->json_is('/object/dolos/1/tags'          => [])
      ->json_is('/object/dolos/1/children/0/category_id'   => 1)
      ->json_is('/object/dolos/1/children/0/category_name' => 'Default')
      ->json_is('/object/dolos/1/children/0/count'         => 0)
      ->json_is('/object/dolos/1/children/0/extra'         => 'plugh')
      ->json_is('/object/dolos/1/children/0/id'            => 3)
      ->json_is('/object/dolos/1/children/0/name'          => 'plugh')
      ->json_is('/object/dolos/1/children/0/short'         => '/h/plugh')
      ->json_is('/object/dolos/1/children/0/url'           => 'https://foo.dolomon.org')
      ->json_is('/object/dolos/1/children/0/tags'          => [])
      ->json_is('/object/dolos/1/children/0/children'      => undef)
      ->json_is('/success'                      => true);

    $t->get_ok('/api/cat/data/42')
      ->status_is(200)
      ->json_is({
        msg     => 'The category you\'re trying to get does not belong to you.',
        success => false,
      });

    $t->get_ok('/api/cat/zip/1')
      ->status_is(200)
      ->content_type_is('application/zip;name=export-category-1.zip')
      ->header_is('Content-Disposition' => 'attachment;filename=export-category-1.zip');
}

sub test_api_tag_2 {
    $t->get_ok('/api/tag/data/2?period=years')
      ->status_is(200)
      ->json_like('/object/dolos/0/created_at'  => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,6}@)
      ->json_like('/max'                        => qr@\d{10}@)
      ->json_like('/min'                        => qr@\d{10}@)
      ->json_like('/data/0/x'                   => qr@\d{10}@)
      ->json_like('/data/1/x'                   => qr@\d{10}@)
      ->json_is('/data/2'                       => undef)
      ->json_is('/data/0/value'                 => 1)
      ->json_is('/data/1/value'                 => 6)
      ->json_is('/object/id'                    => 2)
      ->json_is('/object/name'                  => 'quux')
      ->json_is('/object/dolos/1'               => undef)
      ->json_is('/object/dolos/0/expired'       => undef)
      ->json_is('/object/dolos/0/expires_after' => undef)
      ->json_is('/object/dolos/0/expires_at'    => undef)
      ->json_is('/object/dolos/0/extra'         => 'xyzzy')
      ->json_is('/object/dolos/0/expires_after' => undef)
      ->json_is('/object/dolos/0/category_id'   => 1)
      ->json_is('/object/dolos/0/category_name' => 'Default')
      ->json_is('/object/dolos/0/id'            => 1)
      ->json_is('/object/dolos/0/count'         => 12)
      ->json_is('/object/dolos/0/name'          => 'waldo')
      ->json_is('/object/dolos/0/parent_id'     => undef)
      ->json_is('/object/dolos/0/short'         => '/h/fred')
      ->json_is('/object/dolos/0/url'           => 'https://baz.dolomon.org')
      ->json_is('/object/dolos/0/tags'          => [
            {
                id   => 3,
                name => 'corge'
            },
            {
                id   => 2,
                name => 'quux'
            }
        ])
      ->json_is('/success' => true);

    $t->get_ok('/api/tag/data/2?period=months')
      ->status_is(200)
      ->json_like('/object/dolos/0/created_at'  => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,6}@)
      ->json_like('/max'                        => qr@\d{10}@)
      ->json_like('/min'                        => qr@\d{10}@)
      ->json_like('/data/0/x'                   => qr@\d{10}@)
      ->json_like('/data/1/x'                   => qr@\d{10}@)
      ->json_like('/data/2/x'                   => qr@\d{10}@)
      ->json_is('/data/3'                       => undef)
      ->json_is('/data/0/value'                 => 1)
      ->json_is('/data/1/value'                 => 1)
      ->json_is('/data/2/value'                 => 5)
      ->json_is('/object/id'                    => 2)
      ->json_is('/object/name'                  => 'quux')
      ->json_is('/object/dolos/1'               => undef)
      ->json_is('/object/dolos/0/expired'       => undef)
      ->json_is('/object/dolos/0/expires_after' => undef)
      ->json_is('/object/dolos/0/expires_at'    => undef)
      ->json_is('/object/dolos/0/extra'         => 'xyzzy')
      ->json_is('/object/dolos/0/expires_after' => undef)
      ->json_is('/object/dolos/0/category_id'   => 1)
      ->json_is('/object/dolos/0/category_name' => 'Default')
      ->json_is('/object/dolos/0/id'            => 1)
      ->json_is('/object/dolos/0/count'         => 12)
      ->json_is('/object/dolos/0/name'          => 'waldo')
      ->json_is('/object/dolos/0/parent_id'     => undef)
      ->json_is('/object/dolos/0/short'         => '/h/fred')
      ->json_is('/object/dolos/0/url'           => 'https://baz.dolomon.org')
      ->json_is('/object/dolos/0/tags'          => [
            {
                id   => 3,
                name => 'corge'
            },
            {
                id   => 2,
                name => 'quux'
            }
        ])
      ->json_is('/success' => true);

    $t->get_ok('/api/tag/data/2?period=weeks')
      ->status_is(200)
      ->json_like('/object/dolos/0/created_at'  => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,6}@)
      ->json_like('/max'                        => qr@\d{10}@)
      ->json_like('/min'                        => qr@\d{10}@)
      ->json_like('/data/0/x'                   => qr@\d{10}@)
      ->json_like('/data/1/x'                   => qr@\d{10}@)
      ->json_like('/data/2/x'                   => qr@\d{10}@)
      ->json_is('/data/3'                       => undef)
      ->json_is('/data/0/value'                 => 1)
      ->json_is('/data/1/value'                 => 1)
      ->json_is('/data/2/value'                 => 4)
      ->json_is('/object/id'                    => 2)
      ->json_is('/object/name'                  => 'quux')
      ->json_is('/object/dolos/1'               => undef)
      ->json_is('/object/dolos/0/expired'       => undef)
      ->json_is('/object/dolos/0/expires_after' => undef)
      ->json_is('/object/dolos/0/expires_at'    => undef)
      ->json_is('/object/dolos/0/extra'         => 'xyzzy')
      ->json_is('/object/dolos/0/expires_after' => undef)
      ->json_is('/object/dolos/0/category_id'   => 1)
      ->json_is('/object/dolos/0/category_name' => 'Default')
      ->json_is('/object/dolos/0/id'            => 1)
      ->json_is('/object/dolos/0/count'         => 12)
      ->json_is('/object/dolos/0/name'          => 'waldo')
      ->json_is('/object/dolos/0/parent_id'     => undef)
      ->json_is('/object/dolos/0/short'         => '/h/fred')
      ->json_is('/object/dolos/0/url'           => 'https://baz.dolomon.org')
      ->json_is('/object/dolos/0/tags'          => [
            {
                id   => 3,
                name => 'corge'
            },
            {
                id   => 2,
                name => 'quux'
            }
        ])
      ->json_is('/success' => true);

    $t->get_ok('/api/tag/data/2?period=days')
      ->status_is(200)
      ->json_like('/object/dolos/0/created_at'  => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,6}@)
      ->json_like('/max'                        => qr@\d{10}@)
      ->json_like('/min'                        => qr@\d{10}@)
      ->json_like('/data/0/x'                   => qr@\d{10}@)
      ->json_like('/data/1/x'                   => qr@\d{10}@)
      ->json_like('/data/2/x'                   => qr@\d{10}@)
      ->json_like('/data/3/x'                   => qr@\d{10}@)
      ->json_is('/data/4'                       => undef)
      ->json_is('/data/0/value'                 => 1)
      ->json_is('/data/1/value'                 => 1)
      ->json_is('/data/2/value'                 => 1)
      ->json_is('/data/3/value'                 => 3)
      ->json_is('/object/id'                    => 2)
      ->json_is('/object/name'                  => 'quux')
      ->json_is('/object/dolos/1'               => undef)
      ->json_is('/object/dolos/0/expired'       => undef)
      ->json_is('/object/dolos/0/expires_after' => undef)
      ->json_is('/object/dolos/0/expires_at'    => undef)
      ->json_is('/object/dolos/0/extra'         => 'xyzzy')
      ->json_is('/object/dolos/0/expires_after' => undef)
      ->json_is('/object/dolos/0/category_id'   => 1)
      ->json_is('/object/dolos/0/category_name' => 'Default')
      ->json_is('/object/dolos/0/id'            => 1)
      ->json_is('/object/dolos/0/count'         => 12)
      ->json_is('/object/dolos/0/name'          => 'waldo')
      ->json_is('/object/dolos/0/parent_id'     => undef)
      ->json_is('/object/dolos/0/short'         => '/h/fred')
      ->json_is('/object/dolos/0/url'           => 'https://baz.dolomon.org')
      ->json_is('/object/dolos/0/tags'          => [
            {
                id   => 3,
                name => 'corge'
            },
            {
                id   => 2,
                name => 'quux'
            }
        ])
      ->json_is('/success' => true);

    $t->get_ok('/api/tag/data/2?period=hits')
      ->status_is(200)
      ->json_like('/object/dolos/0/created_at'  => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,6}@)
      ->json_like('/max'                        => qr@\d{10}@)
      ->json_like('/min'                        => qr@\d{10}@)
      ->json_like('/data/0/x'                   => qr@\d{10}@)
      ->json_like('/data/1/x'                   => qr@\d{10}@)
      ->json_like('/data/2/x'                   => qr@\d{10}@)
      ->json_is('/data/3'                       => undef)
      ->json_is('/data/0/value'                 => 1)
      ->json_is('/data/1/value'                 => 2)
      ->json_is('/data/2/value'                 => 1)
      ->json_is('/object/id'                    => 2)
      ->json_is('/object/name'                  => 'quux')
      ->json_is('/object/dolos/1'               => undef)
      ->json_is('/object/dolos/0/expired'       => undef)
      ->json_is('/object/dolos/0/expires_after' => undef)
      ->json_is('/object/dolos/0/expires_at'    => undef)
      ->json_is('/object/dolos/0/extra'         => 'xyzzy')
      ->json_is('/object/dolos/0/expires_after' => undef)
      ->json_is('/object/dolos/0/category_id'   => 1)
      ->json_is('/object/dolos/0/category_name' => 'Default')
      ->json_is('/object/dolos/0/id'            => 1)
      ->json_is('/object/dolos/0/count'         => 12)
      ->json_is('/object/dolos/0/name'          => 'waldo')
      ->json_is('/object/dolos/0/parent_id'     => undef)
      ->json_is('/object/dolos/0/short'         => '/h/fred')
      ->json_is('/object/dolos/0/url'           => 'https://baz.dolomon.org')
      ->json_is('/object/dolos/0/tags'          => [
            {
                id   => 3,
                name => 'corge'
            },
            {
                id   => 2,
                name => 'quux'
            }
        ])
      ->json_is('/success' => true);

    $t->get_ok('/api/tag/data/2?period=hits&aggregate_by=1')
      ->status_is(200)
      ->json_like('/object/dolos/0/created_at'  => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,6}@)
      ->json_like('/max'                        => qr@\d{10}@)
      ->json_like('/min'                        => qr@\d{10}@)
      ->json_like('/data/0/x'                   => qr@\d{10}@)
      ->json_like('/data/1/x'                   => qr@\d{10}@)
      ->json_like('/data/2/x'                   => qr@\d{10}@)
      ->json_like('/data/3/x'                   => qr@\d{10}@)
      ->json_is('/data/4'                       => undef)
      ->json_is('/data/0/value'                 => 1)
      ->json_is('/data/1/value'                 => 1)
      ->json_is('/data/2/value'                 => 1)
      ->json_is('/data/2/value'                 => 1)
      ->json_is('/object/id'                    => 2)
      ->json_is('/object/name'                  => 'quux')
      ->json_is('/object/dolos/1'               => undef)
      ->json_is('/object/dolos/0/expired'       => undef)
      ->json_is('/object/dolos/0/expires_after' => undef)
      ->json_is('/object/dolos/0/expires_at'    => undef)
      ->json_is('/object/dolos/0/extra'         => 'xyzzy')
      ->json_is('/object/dolos/0/expires_after' => undef)
      ->json_is('/object/dolos/0/category_id'   => 1)
      ->json_is('/object/dolos/0/category_name' => 'Default')
      ->json_is('/object/dolos/0/id'            => 1)
      ->json_is('/object/dolos/0/count'         => 12)
      ->json_is('/object/dolos/0/name'          => 'waldo')
      ->json_is('/object/dolos/0/parent_id'     => undef)
      ->json_is('/object/dolos/0/short'         => '/h/fred')
      ->json_is('/object/dolos/0/url'           => 'https://baz.dolomon.org')
      ->json_is('/object/dolos/0/tags'          => [
            {
                id   => 3,
                name => 'corge'
            },
            {
                id   => 2,
                name => 'quux'
            }
        ])
      ->json_is('/success' => true);

    $t->get_ok('/api/tag/data/3?period=years')
      ->status_is(200)
      ->json_like('/object/dolos/0/created_at'  => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,6}@)
      ->json_like('/max'                        => qr@\d{10}@)
      ->json_like('/min'                        => qr@\d{10}@)
      ->json_like('/data/0/x'                   => qr@\d{10}@)
      ->json_like('/data/1/x'                   => qr@\d{10}@)
      ->json_is('/data/2'                       => undef)
      ->json_is('/data/0/value'                 => 1)
      ->json_is('/data/1/value'                 => 6)
      ->json_is('/object/id'                    => 3)
      ->json_is('/object/name'                  => 'corge')
      ->json_is('/object/dolos/1'               => undef)
      ->json_is('/object/dolos/0/expired'       => undef)
      ->json_is('/object/dolos/0/expires_after' => undef)
      ->json_is('/object/dolos/0/expires_at'    => undef)
      ->json_is('/object/dolos/0/extra'         => 'xyzzy')
      ->json_is('/object/dolos/0/expires_after' => undef)
      ->json_is('/object/dolos/0/category_id'   => 1)
      ->json_is('/object/dolos/0/category_name' => 'Default')
      ->json_is('/object/dolos/0/id'            => 1)
      ->json_is('/object/dolos/0/count'         => 12)
      ->json_is('/object/dolos/0/name'          => 'waldo')
      ->json_is('/object/dolos/0/parent_id'     => undef)
      ->json_is('/object/dolos/0/short'         => '/h/fred')
      ->json_is('/object/dolos/0/url'           => 'https://baz.dolomon.org')
      ->json_is('/object/dolos/0/tags'          => [
            {
                id   => 3,
                name => 'corge'
            },
            {
                id   => 2,
                name => 'quux'
            }
        ])
      ->json_is('/success' => true);

    $t->get_ok('/api/tag/data/3?period=months')
      ->status_is(200)
      ->json_like('/object/dolos/0/created_at'  => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,6}@)
      ->json_like('/max'                        => qr@\d{10}@)
      ->json_like('/min'                        => qr@\d{10}@)
      ->json_like('/data/0/x'                   => qr@\d{10}@)
      ->json_like('/data/1/x'                   => qr@\d{10}@)
      ->json_like('/data/2/x'                   => qr@\d{10}@)
      ->json_is('/data/3'                       => undef)
      ->json_is('/data/0/value'                 => 1)
      ->json_is('/data/1/value'                 => 1)
      ->json_is('/data/2/value'                 => 5)
      ->json_is('/object/id'                    => 3)
      ->json_is('/object/name'                  => 'corge')
      ->json_is('/object/dolos/1'               => undef)
      ->json_is('/object/dolos/0/expired'       => undef)
      ->json_is('/object/dolos/0/expires_after' => undef)
      ->json_is('/object/dolos/0/expires_at'    => undef)
      ->json_is('/object/dolos/0/extra'         => 'xyzzy')
      ->json_is('/object/dolos/0/expires_after' => undef)
      ->json_is('/object/dolos/0/category_id'   => 1)
      ->json_is('/object/dolos/0/category_name' => 'Default')
      ->json_is('/object/dolos/0/id'            => 1)
      ->json_is('/object/dolos/0/count'         => 12)
      ->json_is('/object/dolos/0/name'          => 'waldo')
      ->json_is('/object/dolos/0/parent_id'     => undef)
      ->json_is('/object/dolos/0/short'         => '/h/fred')
      ->json_is('/object/dolos/0/url'           => 'https://baz.dolomon.org')
      ->json_is('/object/dolos/0/tags'          => [
            {
                id   => 3,
                name => 'corge'
            },
            {
                id   => 2,
                name => 'quux'
            }
        ])
      ->json_is('/success' => true);

    $t->get_ok('/api/tag/data/3?period=weeks')
      ->status_is(200)
      ->json_like('/object/dolos/0/created_at'  => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,6}@)
      ->json_like('/max'                        => qr@\d{10}@)
      ->json_like('/min'                        => qr@\d{10}@)
      ->json_like('/data/0/x'                   => qr@\d{10}@)
      ->json_like('/data/1/x'                   => qr@\d{10}@)
      ->json_like('/data/2/x'                   => qr@\d{10}@)
      ->json_is('/data/3'                       => undef)
      ->json_is('/data/0/value'                 => 1)
      ->json_is('/data/1/value'                 => 1)
      ->json_is('/data/2/value'                 => 4)
      ->json_is('/object/id'                    => 3)
      ->json_is('/object/name'                  => 'corge')
      ->json_is('/object/dolos/1'               => undef)
      ->json_is('/object/dolos/0/expired'       => undef)
      ->json_is('/object/dolos/0/expires_after' => undef)
      ->json_is('/object/dolos/0/expires_at'    => undef)
      ->json_is('/object/dolos/0/extra'         => 'xyzzy')
      ->json_is('/object/dolos/0/expires_after' => undef)
      ->json_is('/object/dolos/0/category_id'   => 1)
      ->json_is('/object/dolos/0/category_name' => 'Default')
      ->json_is('/object/dolos/0/id'            => 1)
      ->json_is('/object/dolos/0/count'         => 12)
      ->json_is('/object/dolos/0/name'          => 'waldo')
      ->json_is('/object/dolos/0/parent_id'     => undef)
      ->json_is('/object/dolos/0/short'         => '/h/fred')
      ->json_is('/object/dolos/0/url'           => 'https://baz.dolomon.org')
      ->json_is('/object/dolos/0/tags'          => [
            {
                id   => 3,
                name => 'corge'
            },
            {
                id   => 2,
                name => 'quux'
            }
        ])
      ->json_is('/success' => true);

    $t->get_ok('/api/tag/data/3?period=days')
      ->status_is(200)
      ->json_like('/object/dolos/0/created_at'  => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,6}@)
      ->json_like('/max'                        => qr@\d{10}@)
      ->json_like('/min'                        => qr@\d{10}@)
      ->json_like('/data/0/x'                   => qr@\d{10}@)
      ->json_like('/data/1/x'                   => qr@\d{10}@)
      ->json_like('/data/2/x'                   => qr@\d{10}@)
      ->json_like('/data/3/x'                   => qr@\d{10}@)
      ->json_is('/data/4'                       => undef)
      ->json_is('/data/0/value'                 => 1)
      ->json_is('/data/1/value'                 => 1)
      ->json_is('/data/2/value'                 => 1)
      ->json_is('/data/3/value'                 => 3)
      ->json_is('/object/id'                    => 3)
      ->json_is('/object/name'                  => 'corge')
      ->json_is('/object/dolos/1'               => undef)
      ->json_is('/object/dolos/0/expired'       => undef)
      ->json_is('/object/dolos/0/expires_after' => undef)
      ->json_is('/object/dolos/0/expires_at'    => undef)
      ->json_is('/object/dolos/0/extra'         => 'xyzzy')
      ->json_is('/object/dolos/0/expires_after' => undef)
      ->json_is('/object/dolos/0/category_id'   => 1)
      ->json_is('/object/dolos/0/category_name' => 'Default')
      ->json_is('/object/dolos/0/id'            => 1)
      ->json_is('/object/dolos/0/count'         => 12)
      ->json_is('/object/dolos/0/name'          => 'waldo')
      ->json_is('/object/dolos/0/parent_id'     => undef)
      ->json_is('/object/dolos/0/short'         => '/h/fred')
      ->json_is('/object/dolos/0/url'           => 'https://baz.dolomon.org')
      ->json_is('/object/dolos/0/tags'          => [
            {
                id   => 3,
                name => 'corge'
            },
            {
                id   => 2,
                name => 'quux'
            }
        ])
      ->json_is('/success' => true);

    $t->get_ok('/api/tag/data/3?period=hits')
      ->status_is(200)
      ->json_like('/object/dolos/0/created_at'  => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,6}@)
      ->json_like('/max'                        => qr@\d{10}@)
      ->json_like('/min'                        => qr@\d{10}@)
      ->json_like('/data/0/x'                   => qr@\d{10}@)
      ->json_like('/data/1/x'                   => qr@\d{10}@)
      ->json_like('/data/2/x'                   => qr@\d{10}@)
      ->json_is('/data/3'                       => undef)
      ->json_is('/data/0/value'                 => 1)
      ->json_is('/data/1/value'                 => 2)
      ->json_is('/data/2/value'                 => 1)
      ->json_is('/object/id'                    => 3)
      ->json_is('/object/name'                  => 'corge')
      ->json_is('/object/dolos/1'               => undef)
      ->json_is('/object/dolos/0/expired'       => undef)
      ->json_is('/object/dolos/0/expires_after' => undef)
      ->json_is('/object/dolos/0/expires_at'    => undef)
      ->json_is('/object/dolos/0/extra'         => 'xyzzy')
      ->json_is('/object/dolos/0/expires_after' => undef)
      ->json_is('/object/dolos/0/category_id'   => 1)
      ->json_is('/object/dolos/0/category_name' => 'Default')
      ->json_is('/object/dolos/0/id'            => 1)
      ->json_is('/object/dolos/0/count'         => 12)
      ->json_is('/object/dolos/0/name'          => 'waldo')
      ->json_is('/object/dolos/0/parent_id'     => undef)
      ->json_is('/object/dolos/0/short'         => '/h/fred')
      ->json_is('/object/dolos/0/url'           => 'https://baz.dolomon.org')
      ->json_is('/object/dolos/0/tags'          => [
            {
                id   => 3,
                name => 'corge'
            },
            {
                id   => 2,
                name => 'quux'
            }
        ])
      ->json_is('/success' => true);

    $t->get_ok('/api/tag/data/3?period=hits&aggregate_by=1')
      ->status_is(200)
      ->json_like('/object/dolos/0/created_at'  => qr@\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,6}@)
      ->json_like('/max'                        => qr@\d{10}@)
      ->json_like('/min'                        => qr@\d{10}@)
      ->json_like('/data/0/x'                   => qr@\d{10}@)
      ->json_like('/data/1/x'                   => qr@\d{10}@)
      ->json_like('/data/2/x'                   => qr@\d{10}@)
      ->json_like('/data/3/x'                   => qr@\d{10}@)
      ->json_is('/data/4'                       => undef)
      ->json_is('/data/0/value'                 => 1)
      ->json_is('/data/1/value'                 => 1)
      ->json_is('/data/2/value'                 => 1)
      ->json_is('/data/3/value'                 => 1)
      ->json_is('/object/id'                    => 3)
      ->json_is('/object/name'                  => 'corge')
      ->json_is('/object/dolos/1'               => undef)
      ->json_is('/object/dolos/0/expired'       => undef)
      ->json_is('/object/dolos/0/expires_after' => undef)
      ->json_is('/object/dolos/0/expires_at'    => undef)
      ->json_is('/object/dolos/0/extra'         => 'xyzzy')
      ->json_is('/object/dolos/0/expires_after' => undef)
      ->json_is('/object/dolos/0/category_id'   => 1)
      ->json_is('/object/dolos/0/category_name' => 'Default')
      ->json_is('/object/dolos/0/id'            => 1)
      ->json_is('/object/dolos/0/count'         => 12)
      ->json_is('/object/dolos/0/name'          => 'waldo')
      ->json_is('/object/dolos/0/parent_id'     => undef)
      ->json_is('/object/dolos/0/short'         => '/h/fred')
      ->json_is('/object/dolos/0/url'           => 'https://baz.dolomon.org')
      ->json_is('/object/dolos/0/tags'          => [
            {
                id   => 3,
                name => 'corge'
            },
            {
                id   => 2,
                name => 'quux'
            }
        ])
      ->json_is('/success' => true);

    $t->get_ok('/api/tag/data/42')
      ->status_is(200)
      ->json_is({
        msg     => 'The tag you\'re trying to get does not belong to you.',
        success => false,
      });

    $t->get_ok('/api/tag/zip/2')
      ->status_is(200)
      ->content_type_is('application/zip;name=export-tag-2.zip')
      ->header_is('Content-Disposition' => 'attachment;filename=export-tag-2.zip');

    $t->get_ok('/api/tag/zip/3')
      ->status_is(200)
      ->content_type_is('application/zip;name=export-tag-3.zip')
      ->header_is('Content-Disposition' => 'attachment;filename=export-tag-3.zip');
}

sub test_account_management ($not_ldap_account = 0) {
    if ($not_ldap_account) {
    } else {
        $t->get_ok('/user')
          ->status_is(200)
          ->content_like(qr@Error.*This is a LDAP account, you can.*t change account details nor password here\.@s);

        $t->post_ok('/user')
          ->status_is(200)
          ->content_like(qr@Error.*This is a LDAP account, you can.*t change account details nor password here\.@s);

        $t->get_ok('/delete/42')
          ->status_is(302);

        $t->get_ok('/delete/00000000-0000-0000-0000-000000000000')
          ->status_is(302);

        $t->ua->max_redirects(1);

        $t->get_ok('/delete/42')
          ->status_is(200)
          ->content_like(qr@Error.*Unable to find an account with this token\.@s);

        $t->get_ok('/delete/00000000-0000-0000-0000-000000000000')
          ->status_is(200)
          ->content_like(qr@Error.*Unable to find an account with this token\.@s);

        $t->ua->max_redirects(0);
    }
}

sub test_register_account {
    $t->post_ok('/register')
      ->status_is(200)
      ->content_like(qr@Bad CSRF token@);

    my $token = $t->ua->get('/')->res->dom->find('#signup input[name="csrf_token"]')->first->attr('value');

    $t->post_ok('/register' => form => {
            login      => 'zoidberg',
            first_name => 'foo',
            last_name  => 'bar',
            mail       => 'invalid@ddress@mail.example.org',
            password   => 'a',
            password2  => 'b',
            csrf_token => $token,
        })
      ->status_is(200)
      ->content_like(qr@Login already taken\. Choose another one\.@)
      ->content_like(qr@This email address is not valid@)
      ->content_like(qr@Please, choose a password with at least 8 characters\.@)
      ->content_like(qr@The passwords does not match\.@);

    $token = $t->ua->get('/')->res->dom->find('#signup input[name="csrf_token"]')->first->attr('value');
    $t->post_ok('/register' => form => {
            login      => 'foobar',
            first_name => 'foo',
            last_name  => 'bar',
            mail       => 'zoidberg@planetexpress.com',
            password   => 'foobarbazquux',
            password2  => 'foobarbazquux',
            csrf_token => $token,
        })
      ->status_is(200)
      ->content_like(qr@Email address already used\. Choose another one\.@)
      ->content_unlike(qr@Login already taken\. Choose another one\..*This email address is not valid\.*Please, choose a password with at least 8 characters\..*The passwords does not match\.@s);

    $token = $t->ua->get('/')->res->dom->find('#signup input[name="csrf_token"]')->first->attr('value');
    $t->post_ok('/register' => form => {
            login      => 'foobar',
            first_name => 'foo',
            last_name  => 'bar',
            mail       => 'validaddress@mail.example.org',
            password   => 'foobarbazquux',
            password2  => 'foobarbazquux',
            csrf_token => $token,
        })
      ->status_is(200)
      ->content_like(qr@You have been successfully registered\. You will receive a mail containing a link to finish your registration\.@);

    $t->get_ok('/confirm/00000000-0000-0000-0000-000000000000')
      ->status_is(200)
      ->content_like(qr@Unable to find an account with this token: @);

    my $user_token = Dolomon::User->new(app => $t->app)->find_by_('login', 'foobar')->token;

    $t->get_ok('/confirm/'.$user_token)
      ->status_is(200)
      ->content_like(qr@Your account is now confirmed\. You can now login\.@);

    # Can’t find the account since the token has been regenarated
    $t->get_ok('/confirm/'.$user_token)
      ->status_is(200)
      ->content_like(qr@Unable to find an account with this token: @);

    $user_token = Dolomon::User->new(app => $t->app)->find_by_('login', 'foobar')->token;

    $t->get_ok('/confirm/'.$user_token)
      ->status_is(200)
      ->content_like(qr@This account has already been confirmed\.@);
}

sub restore_config {
    $config_file->spurt($config_orig);
}
