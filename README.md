# Dolomon

![Dolomon mascot](https://git.framasoft.org/uploads/project/avatar/180/dolo.png)

## What Dolomon means?

Dolomon was designed as a DOwnLOad MONitor, but it appears that you can monitor visits on pages (see below).

## How Dolomon works?

1. You add an URL in Dolomon (it's called a *dolo* in Dolomon)
2. Dolomon gives you an other URL like https://dolomon.org/3
3. You put the Dolomon URL instead of the target URL in your web site
4. When people use that URL, Dolomon redirects them to the target URL and creates job to increment the counters
5. People are on the target URL
6. Dolomon treats the jobs without impacting the redirection performances

## Install

Check the INSTALL.md file

## Mascot

The Dolomon mascot is called Zag. It has been designed by [Renê Gustavo Miszczak](https://openclipart.org/user-detail/rMiszczak) under the name of [Red Oso](https://openclipart.org/detail/204548/Red%20Oso), have been proposed by [Cyrille Largillier](http://cyrille.largillier.org/) and is in [Public Domain](https://openclipart.org/share)

## License

Copyright 2015 Luc Didry

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

## Powered by

* Mojolicious
* Mojo::Pg
* Minion
* jQuery
* Twitter bootstrap
* see cpanfile for other Perl modules
