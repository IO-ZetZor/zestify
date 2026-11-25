#include "greeter.hpp"
#include "theme.hpp"
#include <QCoreApplication>
#include <QGuiApplication>
#include <QStandardPaths>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QImage>
#include <QTimer>
#include <cstdio>

int main(int argc, char** argv) {
    QStringList args;
    for (int i = 0; i < argc; ++i) args.append(QString::fromLocal8Bit(argv[i]));
    const bool preview = args.contains(QStringLiteral("--preview"));
    QString screenshot, themePath, checkTheme;
    int screenshotDelay = 600;
    for (int i = 1; i < args.size(); ++i) {
        if (args[i] == "--preview") continue;
        if (args[i] == "--theme" && i + 1 < args.size()) { themePath = args[++i]; continue; }
        if (args[i] == "--check-theme" && i + 1 < args.size()) { checkTheme = args[++i]; continue; }
        if (args[i] == "--screenshot" && i + 1 < args.size() && preview) { screenshot = args[++i]; continue; }
        if (args[i] == "--screenshot-delay" && i + 1 < args.size() && preview) {
            bool valid = false;
            screenshotDelay = args[++i].toInt(&valid);
            if (valid && screenshotDelay >= 100 && screenshotDelay <= 30000) continue;
        }
        fprintf(stderr, "usage: zestify-greeter [--theme FILE] [--preview [--screenshot FILE] [--screenshot-delay MS]]\n"
                        "       zestify-greeter --check-theme FILE\n");
        return 2;
    }
    if (!checkTheme.isEmpty()) {
        QCoreApplication app(argc, argv);
        GreeterTheme theme(checkTheme, false);
        fprintf(theme.error() ? stderr : stdout, "%s\n", qPrintable(theme.status()));
        return theme.error() ? 1 : 0;
    }
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("zestify-greeter"));
    const bool allowMissing = themePath.isEmpty();
    if (themePath.isEmpty()) themePath = preview
        ? QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + "/zestify-dm/theme.json"
        : QStringLiteral("/etc/zestify-dm/theme.json");
    GreeterTheme theme(themePath, preview, allowMissing);
    if (theme.error()) fprintf(stderr, "zestify-greeter: %s (using defaults)\n", qPrintable(theme.status()));
    LoginClient client(qEnvironmentVariable("ZESTIFY_DM_SOCKET", QStringLiteral("/run/zestify-dm/control.sock")), preview);
    qmlRegisterSingletonInstance("Zestify.Login", 1, 0, "Login", &client);
    qmlRegisterSingletonInstance("Zestify.Login", 1, 0, "Theme", &theme);
    QQmlApplicationEngine engine;
    engine.load(QUrl(QStringLiteral("qrc:/qml/Login.qml")));
    if (engine.rootObjects().isEmpty()) return 1;
    client.start();
    if (!screenshot.isEmpty()) QTimer::singleShot(screenshotDelay, &app, [&] {
        auto* window = qobject_cast<QQuickWindow*>(engine.rootObjects().first());
        app.exit(window && window->grabWindow().save(screenshot) ? 0 : 1);
    });
    return app.exec();
}
