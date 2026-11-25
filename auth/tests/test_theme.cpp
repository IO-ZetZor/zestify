#include "greeter.hpp"
#include "theme.hpp"
#include <QElapsedTimer>
#include <QFile>
#include <QFont>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QImage>
#include <QJsonDocument>
#include <QQmlApplicationEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QSaveFile>
#include <QTemporaryDir>
#include <QThread>
#include <cmath>
#include <cstdio>
#include <functional>
#include <sys/stat.h>

namespace {
void require(bool condition, const char* message) { if (!condition) throw std::runtime_error(message); }
void pump(int milliseconds) {
    QElapsedTimer timer; timer.start();
    while (timer.elapsed() < milliseconds) { QCoreApplication::processEvents(); QThread::msleep(2); }
}
void until(const std::function<bool()>& check, const char* message, int timeout = 3000) {
    QElapsedTimer timer; timer.start();
    while (!check() && timer.elapsed() < timeout) { QCoreApplication::processEvents(); QThread::msleep(2); }
    require(check(), message);
}
void write(const QString& path, const QByteArray& bytes) {
    QSaveFile file(path);
    require(file.open(QIODevice::WriteOnly) && file.write(bytes) == bytes.size() && file.commit(), "fixture write failed");
}
QObject* visual(QQuickItem* item, const char* name) {
    if (item->objectName() == QLatin1String(name)) return item;
    for (auto* child : item->childItems()) if (auto* result = visual(child, name)) return result;
    return nullptr;
}
QObject* child(QObject* root, const char* name) {
    auto* result = root->findChild<QObject*>(QLatin1String(name));
    if (!result) if (auto* window = qobject_cast<QQuickWindow*>(root)) result = visual(window->contentItem(), name);
    require(result != nullptr, name);
    return result;
}
void invoke(QObject* object, const char* method) { require(QMetaObject::invokeMethod(object, method), method); }
void parsing(GreeterTheme& theme, const QString& path, QTemporaryDir& directory) {
    require(!theme.error() && theme.value("form.width") == 380, "missing optional theme did not use defaults");
    require(theme.setValue("form.width", 460), "valid width rejected");
    for (const auto& entry : std::vector<std::pair<QString, QVariant>>{
        {"form.width", -1}, {"form.width", "460"}, {"background.speed", 0},
        {"colors.text", "invalid-color"}, {"background.source", "https://example.org/video.mp4"},
        {"fonts.file", "file:///tmp/font.ttf"}, {"clock.position.x", 1.5},
        {"clock.visible", 1}, {"version", 2}, {"form.fieldOrder", "username,username"}, {"unknown", 1}})
        require(!theme.setValue(entry.first, entry.second) && theme.value("form.width") == 460, "bad edit mutated theme");
    for (const auto& bytes : {QByteArray("[]"), QByteArray("{"), QByteArray("{\"form\":null}"),
        QByteArray("{\"colors\":{\"text\":null}}"), QByteArray("{\"unknown\":1}"),
        QByteArray(GreeterTheme::MaxThemeBytes + 1, ' ')}) {
        write(path, bytes);
        require(!theme.reload() && theme.value("form.width") == 460, "bad reload lost last good theme");
    }
    write(path, "{\"form\":{\"width\":520},\"background\":{\"source\":\"media #1.png\"}}");
    require(theme.reload() && theme.value("form.width") == 520 && theme.value("clock.fontSize") == 88,
        "partial theme merge failed");
    require(theme.assetUrl("media #1.png").toLocalFile() == directory.filePath("media #1.png"), "relative asset URL corrupt");
    const QString link = directory.filePath("theme-link.json");
    require(QFile::link(path, link), "cannot create theme symlink fixture");
    GreeterTheme linked(link, false);
    require(linked.error(), "theme symlink accepted");
    const QString fifo = directory.filePath("theme.fifo");
    require(mkfifo(QFile::encodeName(fifo).constData(), 0600) == 0, "FIFO fixture failed");
    GreeterTheme pipe(fifo, false);
    require(pipe.error(), "nonregular theme accepted");
    GreeterTheme readonly(path, false);
    require(!readonly.error() && !readonly.setValue("form.width", 600) && !readonly.save(directory.filePath("forbidden.json")),
        "system theme allowed editing");
    readonly.reset();
    require(readonly.value("form.width") == 520, "system theme allowed reset");
    require(!theme.save(link), "theme save followed symlink");
    write(path, "{\"form\":{\"width\":540}}");
    until([&] { return theme.value("form.width") == 540; }, "atomic replacement did not reload theme");
    require(QFile::remove(path), "cannot remove theme fixture");
    pump(250);
    require(theme.value("form.width") == 540 && theme.error(), "deleted theme did not retain last good values");
    write(path, "{\"form\":{\"width\":560}}");
    until([&] { return theme.value("form.width") == 560; }, "recreated theme did not reload");
    theme.reset();
    require(theme.save(path), "cannot save defaults");
    pump(200);
    require(theme.setValue("fonts.family", "monospace"), "preview edit failed");
    write(directory.filePath("unrelated.json"), "{}"); pump(300);
    require(theme.value("fonts.family") == "monospace", "unrelated directory event discarded preview edits");
    theme.reset();
}
void ui(GreeterTheme& theme, LoginClient& login, QQmlApplicationEngine& engine, const QString& directory) {
    engine.load(QUrl("qrc:/qml/Login.qml"));
    require(!engine.rootObjects().isEmpty(), "greeter QML failed to load");
    auto* window = qobject_cast<QQuickWindow*>(engine.rootObjects().first());
    require(window != nullptr, "missing greeter window");
    login.start(); pump(150);
    auto* response = child(window, "response");
    auto* initialAccount = child(window, "username");
    require(initialAccount->property("currentIndex").toInt() >= 0 && !initialAccount->property("editable").toBool(), "account was not preselected in picker");
    require(response->property("visible").toBool() && response->property("enabled").toBool()
        && response->property("activeFocus").toBool() && !login.busy(), "initial password entry was not ready without username typing");
    auto* form = qobject_cast<QQuickItem*>(child(window, "formWidget"));
    require(form != nullptr, "form is not an item");
    const qreal before = form->x();
    require(theme.setValue("form.position.x", 0.20) && theme.setValue("form.position.anchorX", 0.0)
        && theme.setValue("form.width", 460) && theme.setValue("fonts.family", "monospace")
        && theme.setValue("clock.fontSize", 64) && theme.setValue("icons.user.glyph", "★"), "UI theme edit rejected");
    pump(150);
    require(form->x() < before && std::abs(form->x() - 256) < 1 && std::abs(form->width() - 460) < 1, "form position/size did not update");
    auto* username = child(window, "username");
    require(theme.setValue("layout.transparency", 0.6), "transparency edit rejected");
    pump(60);
    require(std::abs(child(response, "loginFieldBackground")->property("opacity").toReal() - 0.4) < 0.001
        && std::abs(child(username, "loginChoiceBackground")->property("opacity").toReal() - 0.4) < 0.001,
        "transparency did not reach login surfaces");
    require(response->property("opacity").toReal() == 1 && username->property("opacity").toReal() == 1,
        "transparency dimmed text or inputs");
    require(!theme.setValue("layout.transparency", 1.1), "invalid transparency accepted");
    theme.setValue("layout.transparency", 0);
    require(username->property("font").value<QFont>().family() == "monospace", "input font not inherited");
    require(child(window, "clockText")->property("font").value<QFont>().pixelSize() == 64, "clock font size not updated");
    QImage iconImage(32, 32, QImage::Format_RGB32); iconImage.fill(QColor("#3399ee"));
    const QString iconPath = directory + "/user #1.png";
    require(iconImage.save(iconPath) && theme.setValue("icons.user.source", "user #1.png"), "icon fixture failed");
    auto* icon = child(child(username, "choiceIcon"), "iconImage");
    until([&] { return icon->property("status").toInt() == 1; }, "custom local icon did not load");
    require(icon->property("source").toUrl().toLocalFile() == iconPath, "icon path resolved incorrectly");
    const QString fontFile = qEnvironmentVariable("ZESTIFY_TEST_FONT_FILE");
    if (!fontFile.isEmpty()) {
        require(theme.setValue("fonts.file", fontFile), "custom font file rejected");
        auto* font = child(window, "bodyFont");
        until([&] { return font->property("status").toInt() == 1; }, "custom font file did not load");
        require(username->property("font").value<QFont>().family() == font->property("name").toString(), "custom font did not reach input");
        theme.setValue("fonts.file", "");
    }
    auto* session = child(window, "sessions");
    const qreal usernameY = username->property("y").toReal();
    require(theme.setValue("form.fieldOrder", "title,session,username,response,message,actions"), "field order rejected");
    pump(150);
    require(session->property("y").toReal() < username->property("y").toReal() && username->property("y").toReal() > usernameY,
        "form field order did not update");
    invoke(session, "incrementCurrentIndex");
    // Open the actual session popup so its delegates are instantiated.
    auto* popup = session->property("popup").value<QObject*>();
    require(popup != nullptr, "session popup missing");
    invoke(popup, "open"); pump(100); invoke(popup, "close");
    auto* editor = child(window, "themeEditor");
    invoke(child(window, "customize"), "clicked");
    until([&] { return editor->property("opened").toBool(); }, "customize button did not open editor");
    pump(100);
    auto* family = child(window, "theme-fonts.family");
    const auto allFonts = theme.fontFamilies();
    for (const auto& font : QFontDatabase::families()) require(allFonts.contains(font), "installed font missing from picker");
    require(family->property("count").toInt() == allFonts.size() && !family->property("editable").toBool(), "font picker did not list all installed fonts");
    const auto fontPopup = family->property("popup").value<QObject*>();
    require(fontPopup != nullptr, "font picker popup missing");
    invoke(fontPopup, "open"); pump(60); invoke(fontPopup, "close");
    auto* search = child(window, "fontSearch-fonts.family");
    search->setProperty("text", "serif"); pump(60);
    QStringList matches;
    for (const auto& font : allFonts) if (font.contains("serif", Qt::CaseInsensitive)) matches.append(font);
    require(family->property("count").toInt() == matches.size() && matches.size() < allFonts.size(), "font search did not filter installed fonts");
    const int fontIndex = matches.indexOf("serif");
    family->setProperty("currentIndex", fontIndex);
    require(QMetaObject::invokeMethod(family, "activated", Q_ARG(int, fontIndex)), "font picker activation failed");
    require(theme.value("fonts.family") == "serif", "editor did not apply font edit");
    // Exercise every editor section; each has a different mix of field types.
    auto* section = child(window, "themeSection");
    for (int index = 0; index < 10; ++index) { section->setProperty("currentIndex", index); pump(60); }
    auto* pickerLoader = child(window, "assetPickerLoader");
    until([&] { return pickerLoader->property("item").value<QObject*>() != nullptr; }, "file picker did not load");
    auto* picker = pickerLoader->property("item").value<QObject*>();
    invoke(child(window, "browse-background.source"), "clicked"); pump(80);
    require(picker->property("visible").toBool(), "background Browse did not open file picker");
    picker->setProperty("selectedFile", QUrl::fromLocalFile(iconPath));
    invoke(picker, "accepted"); invoke(picker, "close");
    require(theme.value("background.source") == iconPath && theme.value("background.type") == "image", "background file selection not applied");
    require(!theme.selectAsset("background.source", QUrl("https://example.org/image.png")), "remote background accepted");
    require(!theme.selectAsset("background.source", QUrl::fromLocalFile(directory + "/missing.png")), "missing background accepted");
    const QString saved = directory + "/saved/theme.json";
    child(window, "themeFilename")->setProperty("text", saved);
    invoke(child(window, "saveTheme"), "clicked");
    require(QFile::exists(saved) && theme.path() == saved, "editor save did not write selected theme");
    require(theme.value("icons.user.source").toString() == iconPath && theme.assetUrl(theme.value("icons.user.source").toString()).toLocalFile() == iconPath,
        "Save As changed relative asset meaning");
    invoke(editor, "close");
    require(response->property("visible").toBool() && response->property("echoMode").toInt() == 2,
        "themed form lost password masking");
    response->setProperty("text", "dummy-test-token"); invoke(window, "submit");
    require(response->property("text").toString().isEmpty() && !login.busy(), "theme form retained response");
    QFile savedFile(saved); require(savedFile.open(QIODevice::ReadOnly), "cannot inspect saved theme");
    require(!savedFile.readAll().contains("dummy-test-token"), "theme save contains credentials");
    // A highly scaled form stays inside a smaller viewport and can scroll.
    window->resize(800, 600); theme.setValue("layout.scale", 2); pump(150);
    const auto bounds = form->mapRectToScene(form->boundingRect());
    require(bounds.left() >= 0 && bounds.right() <= window->width() + 1
        && bounds.top() >= 0 && bounds.bottom() <= window->height() + 1, "scaled form escaped viewport");
    theme.reset(); window->resize(1280, 800); pump(100);
    const QImage image = window->grabWindow();
    require(!image.isNull() && image.size() == QSize(1280, 800), "themed UI did not render");
}
void media(GreeterTheme& theme, LoginClient& login, QQmlApplicationEngine& engine, const QString& video, const QString& animation) {
    QObject* window = engine.rootObjects().first();
    QObject* wallpaper = child(window, "wallpaper");
    QImage still(16, 16, QImage::Format_RGB32); still.fill(QColor("#00aa66"));
    const QString fallback = QFileInfo(theme.path()).absolutePath() + "/fallback.png";
    require(still.save(fallback), "fallback image fixture failed");
    theme.setValue("background.fallback", fallback);
    theme.setValue("background.overlayOpacity", 0);
    theme.setValue("background.source", video);
    theme.setValue("background.type", "video");
    until([&] { return wallpaper->property("videoFrames").toInt() >= 3; }, "video never decoded frames", 8000);
    const int frames = wallpaper->property("videoFrames").toInt();
    pump(1300);
    require(wallpaper->property("videoFrames").toInt() > frames + 5, "short video did not loop");
    theme.setValue("background.paused", true); pump(100);
    const auto paused = wallpaper->property("videoPosition").toReal();
    pump(300);
    require(std::abs(wallpaper->property("videoPosition").toReal() - paused) < 20, "video pause failed");
    theme.setValue("background.paused", false); pump(300);
    login.login("test-user", "hyprland"); pump(100);
    const auto authenticating = wallpaper->property("videoPosition").toReal(); pump(300);
    require(std::abs(wallpaper->property("videoPosition").toReal() - authenticating) < 20, "authentication did not pause video");
    login.cancel();
    theme.setValue("background.source", video + ".missing");
    until([&] { return !wallpaper->property("mediaError").toString().isEmpty(); }, "missing video did not report failure", 8000);
    pump(100);
    auto* quickWindow = qobject_cast<QQuickWindow*>(window);
    require(quickWindow->grabWindow().pixelColor(5, 400) == QColor("#00aa66"), "video failure did not display fallback");
    theme.setValue("background.source", video);
    until([&] { return wallpaper->property("videoFrames").toInt() >= 3 && wallpaper->property("mediaError").toString().isEmpty(); },
        "video did not recover after source change", 8000);
    theme.setValue("background.type", "gradient");
    theme.setValue("background.paused", true);
    theme.setValue("background.type", "video");
    until([&] { return wallpaper->property("videoFrames").toInt() > 0; }, "initially paused video did not decode its first frame", 8000);
    pump(150);
    const int first = wallpaper->property("videoFrames").toInt(); pump(200);
    require(wallpaper->property("videoFrames").toInt() == first, "initially paused video did not stay frozen");
    theme.setValue("background.paused", false);
    theme.setValue("background.source", animation);
    theme.setValue("background.type", "animated");
    auto* animated = child(window, "animatedWallpaper");
    until([&] { return animated->property("frameCount").toInt() > 1; }, "animation did not load");
    const int frame = wallpaper->property("animatedFrame").toInt();
    until([&] { return wallpaper->property("animatedFrame").toInt() != frame; }, "animation frames did not advance");
    theme.setValue("background.paused", true); pump(100);
    const int frozen = wallpaper->property("animatedFrame").toInt(); pump(300);
    require(wallpaper->property("animatedFrame").toInt() == frozen, "animation pause failed");
    theme.setValue("background.type", "gradient");
    require(wallpaper->property("videoFrames").toInt() == 0, "video player was not released");
}
}
int main(int argc, char** argv) {
    QGuiApplication app(argc, argv);
    QTemporaryDir directory;
    try {
        require(directory.isValid(), "temporary theme directory failed");
        const QString path = directory.filePath("theme.json");
        GreeterTheme theme(path, true, true);
        parsing(theme, path, directory);
        require(!theme.selectFont("fonts.family", "not-an-installed-font"), "invalid installed font selection accepted");
        require(theme.selectFont("fonts.family", "monospace"), "generic font alias rejected");
        theme.setValue("fonts.file", "custom.ttf");
        require(theme.selectFont("fonts.family", "serif") && theme.value("fonts.file").toString().isEmpty(), "family selection did not clear file override");
        theme.reset();
        LoginClient login({}, true);
        qmlRegisterSingletonInstance("Zestify.Login", 1, 0, "Theme", &theme);
        qmlRegisterSingletonInstance("Zestify.Login", 1, 0, "Login", &login);
        QQmlApplicationEngine engine;
        ui(theme, login, engine, directory.path());
        if (argc == 3) media(theme, login, engine, QString::fromLocal8Bit(argv[1]), QString::fromLocal8Bit(argv[2]));
        puts("GREETER THEME PASS: validation, reload, editor, geometry, authentication UI and optional media");
        return 0;
    } catch (const std::exception& error) {
        fprintf(stderr, "GREETER THEME FAIL: %s\n", error.what());
        return 1;
    }
}
