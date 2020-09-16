# vim:set sw=4 ts=4 sts=4 ft=perl expandtab:
package Dolomon::DefaultConfig;
require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw($default_config);
our $default_config = {
    prefix               => '/',
    admins               => [],
    theme                => 'default',
    no_register          => 0,
    no_internal_accounts => 0,
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
};

1;
