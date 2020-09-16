SHELL=/bin/bash
EXTRACTDIR=-D lib -D themes/default/templates
POT=themes/default/lib/Dolomon/I18N/dolomon.pot
ENPO=themes/default/lib/Dolomon/I18N/en.po
XGETTEXT=carton exec local/bin/xgettext.pl
CARTON=carton exec
REAL_DOLOMON=script/dolomon
DOLOMON=script/mounter

.PHONY: locales dev devlog minion minion-test cover check-syntax ldap clear-db test clear-and-test full-test

locales:
	$(XGETTEXT) $(EXTRACTDIR) -o $(POT) 2>/dev/null
	$(XGETTEXT) $(EXTRACTDIR) -o $(ENPO) 2>/dev/null

dev:
	MOJO_REVERSE_PROXY=1 $(CARTON) morbo $(DOLOMON) --listen http://0.0.0.0:3000 --watch themes/ --watch dolomon.conf --watch lib/

devlog:
	multitail log/development.log

minion:
	$(CARTON) $(REAL_DOLOMON) minion worker -- -m development

minion-test:
	MOJO_CONFIG=t/dolomon.conf $(CARTON) $(REAL_DOLOMON) minion worker -- -m development

cover:
	PERL5OPT='-Ilib/' $(CARTON) cover --ignore_re '^local/'

check-syntax:
	find lib/ themes/ -name \*.pm -exec carton exec perl -Ilib -c {} \;
	find t/ -name \*.t -exec carton exec perl -Ilib -c {} \;

ldap:
	sudo docker run --privileged -d -p 389:389 rroemhild/test-openldap; exit 0

clear-db:
	pkill --signal SIGTSTP -f "$(DOLOMON)" &
	sudo su postgres -c "echo \"SELECT pg_terminate_backend(pg_stat_activity.pid) FROM pg_stat_activity WHERE pg_stat_activity.datname IN ('dolomon_test_db', 'dolomon_minion_test_db') AND pid <> pg_backend_pid();\" | psql"
	sudo su postgres -c "dropdb dolomon_test_db; createdb -O dolomon_test_user dolomon_test_db; echo 'CREATE EXTENSION \"uuid-ossp\";' | psql dolomon_test_db"
	sudo su postgres -c "dropdb dolomon_minion_test_db; createdb -O dolomon_test_user dolomon_minion_test_db"
	pkill --signal SIGCONT -f "$(DOLOMON)" && exit 0

test:
	DOLOMON_TEST=1 PERL5OPT='-Ilib/' HARNESS_PERL_SWITCHES='-MDevel::Cover=+ignore,^(local|t)/' MOJO_CONFIG=t/dolomon.conf $(CARTON) -- prove -l --failures

test-junit-output:
	DOLOMON_TEST=1 PERL5OPT='-Ilib/' HARNESS_PERL_SWITCHES='-MDevel::Cover=+ignore,^(local|t)/' MOJO_CONFIG=t/dolomon.conf $(CARTON) -- prove -l --failures --formatter TAP::Formatter::JUnit > tap.xml

clear-and-test: clear-db test

full-test: check-syntax ldap just-test
