# directories needed by the build
DIRS := .build .build/clonedigger

# the development environment
DEV_ENV = dev
DEV_ENV_PATH = .tox/$(DEV_ENV)
DEV_ENV_ABS_PATH = $(PWD)/$(DEV_ENV_PATH)
DEV_ENV_ACTIVATE = . $(DEV_ENV_PATH)/bin/activate

CURRENT_VERSION = $(shell python -c "import xtraceback; print xtraceback.__version__")

# nose defaults
NOSETESTS = nosetests
ifndef NOSETESTS_ARGS
NOSETESTS_ARGS =
endif

# tox defaults
TOX = tox --develop
ifeq ($(NOSETESTS_ARGS),)
TOX_ARGS =
else
TOX_ARGS = -- $(NOSETESTS_ARGS)
endif

# the tox environments to test
TEST_ENVS = $(shell grep envlist tox.ini | awk -F= '{print $$2}' | tr -d ,)

# vmake: relaunch in virtualenv as required
SUBMAKE := $(MAKE)
VSUBMAKE := . $(DEV_ENV_ACTIVATE) && $(SUBMAKE)

# silence by default
ifndef VENV_MAKE_DEBUG
VSUBMAKE := @$(VSUBMAKE) --no-print-directory
SUBMAKE := @$(SUBMAKE) --no-print-directory
endif

ifneq ($(VIRTUAL_ENV),$(DEV_ENV_ABS_PATH))
define vmake
	$(warning Relaunching in virtualenv $(DEV_ENV_ABS_PATH)...)
	$(VSUBMAKE) $(1)
endef
else
define vmake
	$(SUBMAKE) $(1)
endef
endif

$(DIRS):
	mkdir -p $@

$(DEV_ENV_ACTIVATE):
	virtualenv $(DEV_ENV_ABS_PATH)
	$(TOX) -e $(DEV_ENV)

.PHONY: virtualenv
virtualenv: $(DEV_ENV_ACTIVATE)

.PHONY: .assert-venv
.assert-venv: virtualenv
	$(if $(VIRTUAL_ENV),,$(error Not in virtualenv $(DEV_ENV_ABS_PATH)))
	$(if $(subst $(DEV_ENV_ABS_PATH),,$(VIRTUAL_ENV)), \
		$(error	Not in correct virtualenv - VIRTUAL_ENV is "$(VIRTUAL_ENV)" \
			when it should be "$(DEV_ENV_ABS_PATH)".))

.PHONY: $(TEST_ENVS)
$(TEST_ENVS): .build
	$(TOX) -e $@ $(TOX_ARGS)

.PHONY: test
test: $(TEST_ENVS)

.PHONY: nosetests
nosetests: .assert-venv
	$(NOSETESTS) $(NOSETESTS_ARGS)

.PHONY: metrics
metrics: test virtualenv
	$(call vmake,.metrics)

.PHONY: .metrics
.metrics: .build/clonedigger .assert-venv
	coverage combine
	coverage xml -o.build/coverage.xml
	coverage html
	-pylint --rcfile=.pylintrc -f parseable xtraceback > .build/pylint
	-pep8 --repeat xtraceback > .build/pep8
	clonedigger --cpd-output -o .build/clonedigger.xml xtraceback
	clonedigger -o .build/clonedigger/index.html xtraceback
	sloccount --wide --details xtraceback > .build/sloccount

.PHONY: doc
doc: .build/doc/index.html

.build/doc/index.html: virtualenv $(shell find doc -type f)
	$(call vmake,.vdoc)

.vdoc: .assert-venv
	sphinx-build -W -b doctest doc .build/doc
#	sphinx-build -W -b spelling doc .build/doc
	sphinx-build -W -b coverage doc .build/doc
#	sphinx-build -W -b linkcheck doc .build/doc
	sphinx-build -W -b html doc .build/doc

.DEFAULT_GOAL: all
all: metrics doc

.PHONY: release
release:
	$(if $(VERSION),,$(error VERSION not set))
	git flow release start $(VERSION)
	sed -i "" "s/$(CURRENT_VERSION)/$(VERSION)/" xtraceback/__init__.py
	git commit -m "version bump" xtraceback/__init__.py
	git flow release finish $(VERSION)
#	git push --all


.PHONY: publish
publish: doc
	git push --tags
	./setup.py sdist register upload upload_sphinx

.PHONY: clean
clean:
	git clean -fdX