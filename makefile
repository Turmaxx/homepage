# Wanted to make this a justfile instead of a makefile since I wanted to explore the features that just offers over make
# instead, however this works for me.

compile:
	hugo
preview:
	hugo -D -E -F --baseURL https://brook-s-homepage.web.app
serve:
	hugo server -D
submodule-clone:
	git clone --recurse-submodules git@github.com:Turmaxx/homepage.git
submodule-update:
	git submodule foreach git pull
