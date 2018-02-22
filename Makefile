EXTRACTDIR=-D lib -D themes/default/templates
POT=themes/default/lib/Dolomon/I18N/dolomon.pot
XGETTEXT=carton exec local/bin/xgettext.pl
CARTON=carton exec
REAL_DOLOMON=script/dolomon
DOLOMON=script/mounter

locales:
	$(XGETTEXT) $(EXTRACTDIR) -o $(POT) 2>/dev/null

push-locales:
	zanata-cli push

pull-locales:
	zanata-cli pull

dev:
	MOJO_REVERSE_PROXY=1 $(CARTON) morbo $(DOLOMON) --listen http://127.0.0.1:8400 --watch themes/ --watch dolomon.conf --watch lib/

devlog:
	multitail log/development.log

minion:
	$(CARTON) $(REAL_DOLOMON) minion worker -- -m development
