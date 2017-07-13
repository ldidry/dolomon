# Dolomon

![Zag, the Dolomon mascot](https://framagit.org/luc/dolomon/raw/master/themes/default/public/img/dolomon.png)

## What Dolomon means?

Dolomon was designed as a DOwnLOad MONitor, but it appears that you can monitor visits on pages (see below).

## How Dolomon works?

1. You add an URL in Dolomon (it's called a *dolo* in Dolomon)
2. Dolomon gives you an other URL like https://dolomon.org/h/3
3. You put the Dolomon URL instead of the target URL in your web site
4. When people use that URL, Dolomon redirects them to the target URL and creates job to increment the counters
5. People are on the target URL
6. Dolomon treats the jobs without impacting the redirection performances

## Install

Check the INSTALL.md file

## Mascot

The Dolomon mascot is called Zag. It has been initially designed by [Renê Gustavo Miszczak](https://openclipart.org/user-detail/rMiszczak) under the name of [Red Oso](https://openclipart.org/detail/204548/Red%20Oso), have been proposed by [Cyrille Largillier](http://cyrille.largillier.org/), is in [Public Domain](https://openclipart.org/share) and has been slightly modified for Dolomon.

## License

Licensed under the GNU AGPLv3, see the [LICENSE file](LICENSE).

## Powered by

* Mojolicious
* Mojo::Pg
* Minion
* jQuery
* Twitter bootstrap
* see cpanfile for other Perl modules
