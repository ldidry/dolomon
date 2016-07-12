package Dolomon::Application;
use Mojo::Base 'Dolomon::Db';

has 'table' => 'applications';
has 'name';
has 'user_id';
has 'app_id';
has 'app_secret';

1;
