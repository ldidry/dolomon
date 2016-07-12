package Dolomon::DoloHit;
use Mojo::Base 'Dolomon::Db';

has 'table' => 'dolos_hits';
has 'id';
has 'dolo_id';
has 'ts';
has 'referrer';

1;
