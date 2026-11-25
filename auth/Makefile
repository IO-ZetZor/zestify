CXX ?= c++
BUILD ?= build
PREFIX ?= /usr
CPPFLAGS += $(shell pkg-config --cflags Qt6Core Qt6Network Qt6Quick libsystemd)
CXXFLAGS ?= -O2 -g
CXXFLAGS += -std=c++17 -Wall -Wextra -Wpedantic -fPIC
CORE_LIBS = $(shell pkg-config --libs Qt6Core libsystemd) -lpam
GUI_LIBS = $(shell pkg-config --libs Qt6Core Qt6Network Qt6Quick)
MOC = $(shell pkg-config --variable=libexecdir Qt6Core)/moc
RCC = $(shell pkg-config --variable=libexecdir Qt6Core)/rcc

.PHONY: all test install clean
all: $(BUILD)/zestify-dm $(BUILD)/zestify-greeter

$(BUILD):
	mkdir -p $@

$(BUILD)/zestify-dm: daemon.cpp protocol.cpp config.cpp pam_session.cpp users.cpp protocol.hpp config.hpp pam_session.hpp users.hpp | $(BUILD)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) daemon.cpp protocol.cpp config.cpp pam_session.cpp users.cpp -o $@ $(CORE_LIBS) $(LDFLAGS)

$(BUILD)/moc_greeter.cpp: greeter.hpp | $(BUILD)
	$(MOC) $< -o $@

$(BUILD)/moc_theme.cpp: theme.hpp | $(BUILD)
	$(MOC) $< -o $@

$(BUILD)/qml.cpp: greeter.qrc $(wildcard qml/*.qml) theme-schema.json | $(BUILD)
	$(RCC) $< -o $@

$(BUILD)/zestify-greeter: greeter_main.cpp greeter.cpp greeter.hpp theme.cpp theme.hpp users.cpp users.hpp $(BUILD)/moc_greeter.cpp $(BUILD)/moc_theme.cpp $(BUILD)/qml.cpp protocol.cpp protocol.hpp
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -I. greeter_main.cpp greeter.cpp theme.cpp users.cpp protocol.cpp $(BUILD)/moc_greeter.cpp $(BUILD)/moc_theme.cpp $(BUILD)/qml.cpp -o $@ $(GUI_LIBS) $(LDFLAGS)

$(BUILD)/pam_test.so: tests/pam_test.cpp | $(BUILD)
	$(CXX) $(CXXFLAGS) -shared $< -o $@ -lpam $(LDFLAGS)

$(BUILD)/test-auth: tests/test_auth.cpp protocol.cpp config.cpp pam_session.cpp users.cpp protocol.hpp config.hpp pam_session.hpp users.hpp | $(BUILD)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -I. tests/test_auth.cpp protocol.cpp config.cpp pam_session.cpp users.cpp -o $@ $(CORE_LIBS) $(LDFLAGS)

$(BUILD)/test-greeter-client: tests/test_greeter_client.cpp greeter.cpp users.cpp protocol.cpp greeter.hpp users.hpp protocol.hpp $(BUILD)/moc_greeter.cpp
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -I. tests/test_greeter_client.cpp greeter.cpp users.cpp protocol.cpp $(BUILD)/moc_greeter.cpp -o $@ $(GUI_LIBS) $(LDFLAGS)

$(BUILD)/test-greeter-theme: tests/test_theme.cpp greeter.cpp theme.cpp users.cpp protocol.cpp greeter.hpp theme.hpp users.hpp protocol.hpp $(BUILD)/moc_greeter.cpp $(BUILD)/moc_theme.cpp $(BUILD)/qml.cpp
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -I. tests/test_theme.cpp greeter.cpp theme.cpp users.cpp protocol.cpp $(BUILD)/moc_greeter.cpp $(BUILD)/moc_theme.cpp $(BUILD)/qml.cpp -o $@ $(GUI_LIBS) $(LDFLAGS)

test: all $(BUILD)/test-auth $(BUILD)/pam_test.so $(BUILD)/test-greeter-client $(BUILD)/test-greeter-theme
	$(BUILD)/test-auth $(abspath $(BUILD)/pam_test.so)
	$(BUILD)/zestify-dm --check-config integration/config.json
	python3 tests/test_greeter.py $(abspath $(BUILD)/zestify-greeter) $(abspath $(BUILD)/test-greeter-client)

# Install the standalone login manager separately from the user's desktop shell.
# Enabling display-manager.service remains an explicit administrator operation.
install: all
	install -Dm755 $(BUILD)/zestify-dm $(DESTDIR)$(PREFIX)/bin/zestify-dm
	install -Dm755 $(BUILD)/zestify-greeter $(DESTDIR)$(PREFIX)/bin/zestify-greeter
	install -Dm644 integration/zestify-dm.service $(DESTDIR)$(PREFIX)/lib/systemd/system/zestify-dm.service
	install -Dm644 integration/zestify-dm.sysusers $(DESTDIR)$(PREFIX)/lib/sysusers.d/zestify-dm.conf
	install -Dm644 integration/zestify-dm.tmpfiles $(DESTDIR)$(PREFIX)/lib/tmpfiles.d/zestify-dm.conf
	install -Dm644 integration/pam-login $(DESTDIR)/etc/pam.d/zestify-dm
	install -Dm644 integration/pam-greeter $(DESTDIR)/etc/pam.d/zestify-greeter
	install -d -m755 $(DESTDIR)/etc/zestify-dm
	if test ! -e $(DESTDIR)/etc/zestify-dm/config.json; then install -m644 integration/config.json $(DESTDIR)/etc/zestify-dm/config.json; fi
	if test ! -e $(DESTDIR)/etc/zestify-dm/theme.json; then install -m644 integration/theme.json $(DESTDIR)/etc/zestify-dm/theme.json; fi
	install -Dm644 themes/split.json $(DESTDIR)$(PREFIX)/share/zestify-dm/themes/split.json
	install -Dm644 themes/minimal.json $(DESTDIR)$(PREFIX)/share/zestify-dm/themes/minimal.json

clean:
	rm -rf -- $(BUILD)
