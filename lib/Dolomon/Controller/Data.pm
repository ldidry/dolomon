package Dolomon::Controller::Data;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON qw(true false decode_json);
use Dolomon::Export;
use Try::Tiny;

sub index {
    my $c = shift;

    my $exports = $c->current_user->get_exports();
    my $pending = $exports->grep(sub {
        return !defined($_->finished_at);
    })->size;
    my $finished = $exports->grep(sub {
        return (defined($_->finished_at) && !$_->expired);
    });
    return $c->render(
        template => 'data/index',
        pending  => $pending,
        finished => $finished
    );
}

sub export {
    my $c = shift;

    my $user_id = $c->current_user->id;

    my $export = Dolomon::Export->new(app => $c)->create({ user_id => $user_id });
    my $subject = $c->l('Dolomon data export');
    my $body    = $c->l("Your data export is ready for download.\n");
       $body   .= $c->l('Go on %1 to download your datas (link available one week).', $c->url_for('download_data', token => $export->token, format => 'json')->to_abs);
       $body   .= "\n-- \n";
       $body   .= $c->l("Kind regards\n");
       $body   .= $c->config('signature');

    $c->app->minion->enqueue(export_data => [
        $user_id,
        $export->token,
        $subject,
        $body
    ]);

    $c->flash(
        msg => {
            title => $c->l('Your data export is about to be processed.'),
            class => 'alert-info',
            text  => $c->l('You will receive a mail with a link to download your data once ready.')
        }
    );

    return $c->redirect_to($c->url_for('export-import'));
}

sub import {
    my $c      = shift;
    my $upload = $c->param('file');
    my $time   = time;

    try {
        my $data = decode_json($upload->slurp);
        my $file = Mojo::File->new('imports', $c->current_user->id.'-'.$time.'-'.$upload->filename);
        $upload->move_to($file);

        my $subject = $c->l('Dolomon data import');
        my $body    = $c->l("Your data import has been processed, you should see your data on %1.\n", $c->url_for('/')->to_abs);
        my $rename  = "\n";
           $rename .= $c->l('However, some elements have been renamed:');
           $rename .= "\n";
        my $r_cats  = $c->l('Categories');
        my $r_tags  = $c->l('Tags');
        my $r_apps  = $c->l('Applications');
        my $r_dolos = $c->l('Dolos (not renamed but the URL have changed)');
        my $tail   .= "\n-- \n";
           $tail   .= $c->l("Kind regards\n");
           $tail   .= $c->config('signature');
        $c->app->minion->enqueue(import_data => [
            $c->current_user->id,
            $file->to_string,
            $time,
            $subject,
            $body,
            $rename,
            $r_cats,
            $r_tags,
            $r_apps,
            $r_dolos,
            $tail
        ]);

        $c->flash(
            msg => {
                title => $c->l('Your data import is about to be processed.'),
                class => 'alert-info',
                text  => $c->l('You will receive a mail once your file has been processed.')
            }
        );
    } catch {
        $c->flash(
            msg => {
                title => $c->l('Improper data.'),
                class => 'alert-danger',
                text  => $c->l('The file you want to import doesn’t seem to contain valid JSON. It will not be processed')
            }
        );
    };

    return $c->redirect_to($c->url_for('export-import'));
}

sub download {
    my $c = shift;
    my $token = $c->param('token');

    if ($c->is_user_authenticated) {
        return $c->reply->not_found unless $token;

        # Check that this is the good user that tries to get the data
        my $export = Dolomon::Export->new(app => $c)->find_by_fields_({ token => $token, user_id => $c->current_user->id, expired => 0 });
        return $c->reply->not_found unless $export->id;

        $c->res->headers->cache_control('no-store');
        $c->res->headers->content_disposition('attachment');
        return $c->reply->static(Mojo::File->new('..', '..', '..', 'exports', $token.'.json'));
    } else {
        return $c->redirect_to($c->url_for('index')->query(goto => $c->url_for('export-import').'#'.$token));
    }
}

1;
