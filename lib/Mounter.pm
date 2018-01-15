package Mounter;
use Mojo::Base 'Mojolicious';
use FindBin qw($Bin);
use File::Spec qw(catfile);

# This method will run once at server start
sub startup {
    my $self = shift;

    push @{$self->commands->namespaces}, 'Dolomon::Command';

    my $config = $self->plugin('Config' =>
        {
            file    => File::Spec->catfile($Bin, '..' ,'dolomon.conf'),
            default => {
                prefix               => '/',
                admins               => [],
                theme                => 'default',
                no_register          => 0,
                counter_delay        => 0,
                do_not_count_spiders => 0,
                mail      => {
                    how  => 'sendmail',
                    from => 'noreply@dolomon.org'
                },
                signature => 'Dolomon',
                keep_hits => {
                    uber_precision  => 3,
                    day_precision   => 90,
                    week_precision  => 12,
                    month_precision => 36,
                }
            }
        }
    );

    # Themes handling
    shift @{$self->static->paths};
    if ($config->{theme} ne 'default') {
        my $theme = $self->home->rel_file('themes/'.$config->{theme});
        push @{$self->static->paths}, $theme.'/public' if -d $theme.'/public';
    }
    push @{$self->static->paths}, $self->home->rel_file('themes/default/public');

    $self->plugin('StaticCache');

    $self->plugin('Mount' => {$config->{prefix} => File::Spec->catfile($Bin, '..', 'script', 'dolomon')});
}

1;
